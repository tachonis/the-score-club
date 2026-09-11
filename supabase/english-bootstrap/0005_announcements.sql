-- =============================================================================
-- ENGLISH BOOTSTRAP — DO NOT APPLY TO GREEK PRODUCTION
-- =============================================================================
-- Equivalent of supabase/migrations/20260911120000_announcements.sql,
-- without the Greek first-matchday unpublished draft.
-- Apply ONLY to English hosted project, never via unscoped `supabase db push`.
-- =============================================================================

-- Announcements v1: club notices, per-user read state, and announcement
-- push destinations. Additive only.

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null
    constraint announcements_title_check check (
      char_length(btrim(title)) between 1 and 120
    ),
  body text not null
    constraint announcements_body_check check (
      char_length(btrim(body)) between 1 and 8000
    ),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  created_by uuid
    constraint announcements_created_by_fkey
    references auth.users (id) on delete set null,
  is_published boolean not null default false,
  category text
    constraint announcements_category_check check (
      category is null
      or category in ('general', 'matchday', 'cup', 'rules')
    ),
  constraint announcements_published_consistency_check check (
    (is_published = true and published_at is not null)
    or
    (is_published = false and published_at is null)
  )
);

create index if not exists announcements_published_at_idx
  on public.announcements (published_at desc)
  where is_published = true;

create index if not exists announcements_created_at_idx
  on public.announcements (created_at desc);

create table if not exists public.announcement_reads (
  announcement_id uuid not null
    constraint announcement_reads_announcement_id_fkey
    references public.announcements (id) on delete cascade,
  user_id uuid not null
    constraint announcement_reads_user_id_fkey
    references auth.users (id) on delete cascade,
  read_at timestamptz not null default now(),
  constraint announcement_reads_pkey primary key (announcement_id, user_id)
);

create index if not exists announcement_reads_user_id_idx
  on public.announcement_reads (user_id);

create or replace function public.sync_announcement_published_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.title := btrim(new.title);
  new.body := btrim(new.body);

  if new.category is not null then
    new.category := btrim(new.category);
    if new.category = '' then
      new.category := null;
    end if;
  end if;

  if new.is_published then
    new.published_at := coalesce(new.published_at, now());
  else
    new.published_at := null;
  end if;

  return new;
end;
$function$;

drop trigger if exists announcements_published_at_sync on public.announcements;
create trigger announcements_published_at_sync
before insert or update on public.announcements
for each row
execute function public.sync_announcement_published_at();

create or replace function public.mark_announcement_read(
  p_announcement_id uuid
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

  if not exists (
    select 1
    from public.announcements as announcement
    where announcement.id = p_announcement_id
      and (
        announcement.is_published = true
        or (select public.is_admin())
      )
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'The announcement was not found';
  end if;

  insert into public.announcement_reads (
    announcement_id,
    user_id
  )
  values (
    p_announcement_id,
    v_user_id
  )
  on conflict (announcement_id, user_id) do nothing;
end;
$function$;

create or replace function public.count_unread_announcements()
returns integer
language plpgsql
stable
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

  return (
    select count(*)::integer
    from public.announcements as announcement
    where announcement.is_published = true
      and not exists (
        select 1
        from public.announcement_reads as read_row
        where read_row.announcement_id = announcement.id
          and read_row.user_id = v_user_id
      )
  );
end;
$function$;

alter table public.announcements enable row level security;
alter table public.announcement_reads enable row level security;

drop policy if exists "Authenticated users can view published announcements"
  on public.announcements;
create policy "Authenticated users can view published announcements"
  on public.announcements
  for select
  to authenticated
  using (
    is_published = true
    or (select public.is_admin())
  );

drop policy if exists "Admins can create announcements"
  on public.announcements;
create policy "Admins can create announcements"
  on public.announcements
  for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists "Admins can update announcements"
  on public.announcements;
create policy "Admins can update announcements"
  on public.announcements
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists "Admins can delete announcements"
  on public.announcements;
create policy "Admins can delete announcements"
  on public.announcements
  for delete
  to authenticated
  using ((select public.is_admin()));

drop policy if exists "Users can view their own announcement reads"
  on public.announcement_reads;
create policy "Users can view their own announcement reads"
  on public.announcement_reads
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all privileges on table public.announcements
  from public, anon, authenticated;
revoke all privileges on table public.announcement_reads
  from public, anon, authenticated;

grant select, insert, update, delete on table public.announcements
  to authenticated;
grant select on table public.announcement_reads to authenticated;

grant all privileges on table public.announcements to service_role;
grant all privileges on table public.announcement_reads to service_role;

revoke execute on function public.mark_announcement_read(uuid)
  from public, anon;
grant execute on function public.mark_announcement_read(uuid)
  to authenticated, service_role;

revoke execute on function public.count_unread_announcements()
  from public, anon;
grant execute on function public.count_unread_announcements()
  to authenticated, service_role;

revoke execute on function public.sync_announcement_published_at()
  from public, anon, authenticated;

alter table public.push_broadcasts
  drop constraint if exists push_broadcasts_destination_check;

alter table public.push_broadcasts
  add constraint push_broadcasts_destination_check check (
    destination in (
      'home',
      'predictions',
      'standings',
      'league-phase',
      'rules',
      'announcements'
    )
    or destination ~* '^[Aa]nnouncements/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  );

