-- Throwaway local Postgres stub ONLY.
-- Do not apply to hosted Greek or English Supabase (those already have Auth).

do $guard$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'auth'
      and table_name = 'users'
      and column_name = 'email'
  ) then
    raise exception
      'local_auth_stub.sql must not be applied to a real Supabase project.';
  end if;
end
$guard$;

create role if not exists anon nologin;
create role if not exists authenticated nologin;
create role if not exists service_role nologin;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
