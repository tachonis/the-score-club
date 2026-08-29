-- Username format for public.profiles.
--
-- Additive CHECK only. Does not modify rows, RLS, grants, or Cup tables.
-- Do not db push. Do not repair migration history. Apply manually after review.
--
-- 30 characters is within cup_participants.username_snapshot (1–100), so
-- create_players_cup cannot fail on username length after this constraint.

do $$
declare
  violating text;
begin
  select string_agg(
    profile.id::text || ' / ' || profile.username,
    E'\n'
    order by profile.username
  )
  into violating
  from public.profiles as profile
  where profile.username is distinct from btrim(profile.username)
     or char_length(profile.username) < 3
     or char_length(profile.username) > 30
     or profile.username !~ '^[A-Za-z0-9_.ΆΈ-ΊΌΎ-ώ-]+$';

  if violating is not null then
    raise exception
      'Cannot add profiles_username_format_check; existing usernames violate the 3–30 policy:%',
      E'\n' || violating;
  end if;
end $$;

alter table public.profiles
  add constraint profiles_username_format_check
  check (
    username = btrim(username)
    and char_length(username) between 3 and 30
    and username ~ '^[A-Za-z0-9_.ΆΈ-ΊΌΎ-ώ-]+$'
  );
