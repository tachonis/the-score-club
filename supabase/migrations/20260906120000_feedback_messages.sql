-- Player contact / feedback inbox v1.
-- This migration only adds new objects. It does not change scoring, Auth,
-- or any existing table, function, policy, grant or row.

create table if not exists public.feedback_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint feedback_messages_user_id_fkey
    references auth.users (id) on delete cascade,
  category text not null
    constraint feedback_messages_category_check check (
      category in ('bug', 'account', 'suggestion', 'other')
    ),
  message text not null
    constraint feedback_messages_message_check check (
      char_length(btrim(message)) between 1 and 1000
    ),
  status text not null default 'new'
    constraint feedback_messages_status_check check (
      status in ('new', 'read', 'resolved')
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid
    constraint feedback_messages_resolved_by_fkey
    references public.profiles (id) on delete set null,
  constraint feedback_messages_resolved_consistency_check check (
    (status = 'resolved' and resolved_at is not null and resolved_by is not null)
    or
    (status <> 'resolved' and resolved_at is null and resolved_by is null)
  )
);

create index if not exists feedback_messages_created_at_idx
  on public.feedback_messages (created_at desc);

create index if not exists feedback_messages_status_created_at_idx
  on public.feedback_messages (status, created_at desc);

create index if not exists feedback_messages_user_id_idx
  on public.feedback_messages (user_id);

-- Browser writes go through RPCs so a player cannot spoof user_id or status.
create or replace function public.submit_feedback(
  p_category text,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_message text := btrim(coalesce(p_message, ''));
  v_id uuid;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required';
  end if;

  if not exists (
    select 1
    from public.profiles as profile
    where profile.id = v_user_id
      and profile.status = 'active'
  ) then
    raise exception using
      errcode = '42501',
      message = 'An active account is required';
  end if;

  if p_category is null
    or p_category not in ('bug', 'account', 'suggestion', 'other')
  then
    raise exception using
      errcode = '22023',
      message = 'A valid category is required';
  end if;

  if char_length(v_message) not between 1 and 1000 then
    raise exception using
      errcode = '22023',
      message = 'The message must be between 1 and 1000 characters';
  end if;

  insert into public.feedback_messages (
    user_id,
    category,
    message
  )
  values (
    v_user_id,
    p_category,
    v_message
  )
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.get_feedback_messages()
returns table (
  id uuid,
  user_id uuid,
  username text,
  email text,
  category text,
  message text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  resolved_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not (select public.is_admin()) then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  return query
  select
    feedback.id,
    feedback.user_id,
    profile.username,
    account.email::text,
    feedback.category,
    feedback.message,
    feedback.status,
    feedback.created_at,
    feedback.updated_at,
    feedback.resolved_at
  from public.feedback_messages as feedback
  join public.profiles as profile
    on profile.id = feedback.user_id
  left join auth.users as account
    on account.id = feedback.user_id
  order by feedback.created_at desc;
end;
$function$;

create or replace function public.count_new_feedback_messages()
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not (select public.is_admin()) then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  return (
    select count(*)::integer
    from public.feedback_messages as feedback
    where feedback.status = 'new'
  );
end;
$function$;

create or replace function public.set_feedback_status(
  p_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
begin
  if v_admin_id is null or not (select public.is_admin()) then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  if p_status is null
    or p_status not in ('new', 'read', 'resolved')
  then
    raise exception using
      errcode = '22023',
      message = 'A valid status is required';
  end if;

  update public.feedback_messages as feedback
  set
    status = p_status,
    updated_at = now(),
    resolved_at = case
      when p_status = 'resolved' then now()
      else null
    end,
    resolved_by = case
      when p_status = 'resolved' then v_admin_id
      else null
    end
  where feedback.id = p_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'The message was not found';
  end if;
end;
$function$;

alter table public.feedback_messages enable row level security;

-- No Data API policies: browser access is RPC-only.
revoke all privileges on table public.feedback_messages
  from anon, authenticated;
grant all privileges on table public.feedback_messages to service_role;

revoke execute on function public.submit_feedback(text, text)
  from public, anon;
grant execute on function public.submit_feedback(text, text)
  to authenticated, service_role;

revoke execute on function public.get_feedback_messages()
  from public, anon;
grant execute on function public.get_feedback_messages()
  to authenticated, service_role;

revoke execute on function public.count_new_feedback_messages()
  from public, anon;
grant execute on function public.count_new_feedback_messages()
  to authenticated, service_role;

revoke execute on function public.set_feedback_status(uuid, text)
  from public, anon;
grant execute on function public.set_feedback_status(uuid, text)
  to authenticated, service_role;
