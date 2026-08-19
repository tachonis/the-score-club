-- Push Notifications v1: per-device Web Push subscriptions and the admin
-- broadcast audit trail.
-- This migration only adds new objects. It does not change or delete any
-- existing table, function, policy, grant or row.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint push_subscriptions_user_id_fkey
    references auth.users (id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_subscriptions_endpoint_key unique (endpoint),
  constraint push_subscriptions_endpoint_check check (
    endpoint like 'https://%'
    and char_length(endpoint) <= 2048
  ),
  constraint push_subscriptions_p256dh_check check (
    char_length(p256dh) between 1 and 255
  ),
  constraint push_subscriptions_auth_check check (
    char_length(auth) between 1 and 255
  ),
  constraint push_subscriptions_user_agent_check check (
    user_agent is null or char_length(user_agent) <= 400
  )
);

create index if not exists push_subscriptions_user_id_idx
  on public.push_subscriptions (user_id);

create table if not exists public.push_broadcasts (
  id uuid primary key default gen_random_uuid(),
  sent_by uuid
    constraint push_broadcasts_sent_by_fkey
    references public.profiles (id) on delete set null,
  title text not null,
  body text not null,
  destination text not null
    constraint push_broadcasts_destination_check check (
      destination in (
        'home',
        'predictions',
        'standings',
        'league-phase',
        'rules'
      )
    ),
  attempted_count integer not null default 0,
  success_count integer not null default 0,
  gone_count integer not null default 0,
  error_count integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists push_broadcasts_sent_by_created_at_idx
  on public.push_broadcasts (sent_by, created_at desc);

-- The browser never writes to push_subscriptions directly. These RPCs always
-- bind the row to the caller, so a player cannot store a subscription for
-- another user or read anyone else's endpoint.
create or replace function public.upsert_my_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  if p_endpoint is null
    or p_endpoint not like 'https://%'
    or char_length(p_endpoint) > 2048
  then
    raise exception using
      errcode = '22023',
      message = 'A valid push endpoint is required';
  end if;

  if p_p256dh is null
    or char_length(p_p256dh) not between 1 and 255
    or p_auth is null
    or char_length(p_auth) not between 1 and 255
  then
    raise exception using
      errcode = '22023',
      message = 'Valid push encryption keys are required';
  end if;

  -- A browser that later signs in as another player re-binds the same
  -- endpoint instead of leaving it attached to the previous account.
  insert into public.push_subscriptions (
    user_id,
    endpoint,
    p256dh,
    auth,
    user_agent
  )
  values (
    v_user_id,
    p_endpoint,
    p_p256dh,
    p_auth,
    left(p_user_agent, 400)
  )
  on conflict (endpoint) do update
  set
    user_id = v_user_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    updated_at = now();
end;
$function$;

create or replace function public.delete_my_push_subscription(
  p_endpoint text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  delete from public.push_subscriptions
  where endpoint = p_endpoint
    and user_id = v_user_id;
end;
$function$;

create or replace function public.delete_all_my_push_subscriptions()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  delete from public.push_subscriptions
  where user_id = v_user_id;
end;
$function$;

-- Only the sender (service role) may read endpoints, and only for players
-- whose account is still active.
create or replace function public.get_active_push_subscriptions()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth_secret text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    subscription.id,
    subscription.endpoint,
    subscription.p256dh,
    subscription.auth
  from public.push_subscriptions as subscription
  join public.profiles as profile
    on profile.id = subscription.user_id
  where profile.status = 'active'
  order by subscription.created_at;
$function$;

alter table public.push_subscriptions enable row level security;
alter table public.push_broadcasts enable row level security;

drop policy if exists "Users can view their own push subscriptions"
  on public.push_subscriptions;
create policy "Users can view their own push subscriptions"
  on public.push_subscriptions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Admins can view push broadcasts"
  on public.push_broadcasts;
create policy "Admins can view push broadcasts"
  on public.push_broadcasts
  for select
  to authenticated
  using ((select public.is_admin()));

-- No insert, update or delete policy exists for either table, so the Data API
-- rejects every browser write even before column grants are considered.
revoke all privileges on table public.push_subscriptions
  from anon, authenticated;
grant select on table public.push_subscriptions to authenticated;

revoke all privileges on table public.push_broadcasts
  from anon, authenticated;
grant select on table public.push_broadcasts to authenticated;

grant all privileges on table public.push_subscriptions to service_role;
grant all privileges on table public.push_broadcasts to service_role;

revoke execute on function public.upsert_my_push_subscription(
  text, text, text, text
) from public, anon;
grant execute on function public.upsert_my_push_subscription(
  text, text, text, text
) to authenticated, service_role;

revoke execute on function public.delete_my_push_subscription(text)
  from public, anon;
grant execute on function public.delete_my_push_subscription(text)
  to authenticated, service_role;

revoke execute on function public.delete_all_my_push_subscriptions()
  from public, anon;
grant execute on function public.delete_all_my_push_subscriptions()
  to authenticated, service_role;

revoke execute on function public.get_active_push_subscriptions()
  from public, anon, authenticated;
grant execute on function public.get_active_push_subscriptions()
  to service_role;
