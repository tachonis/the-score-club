-- Badges foundation: definitions, earned instances, RLS and grants.
--
-- Additive only. No award engine, no hooks into set_match_result /
-- set_long_term_outcome / players_cup_apply, and no player-profile UI.
-- Authenticated clients may read definitions and awards so a later profile
-- page can join metadata onto earned badges. There is still no catalogue
-- route: database readability is not UI visibility.
--
-- award_scope is the relational duplicate-prevention key. Repeatability
-- lives on badge_definitions; a partial unique index cannot see that table,
-- so definitions expose a generated award_scope and awards reference
-- (code, award_scope). Callers cannot mark Exact Machine as a matchday
-- award, and cannot mark Sharp Shooter as a season award.

create table public.badge_definitions (
  code text primary key,
  title text not null,
  description text not null,
  image_path text not null,
  repeatable boolean not null,
  category text not null,
  sort_order integer not null,
  award_scope text generated always as (
    case
      when repeatable then 'matchday'
      else 'season'
    end
  ) stored,
  created_at timestamptz not null default now(),
  constraint badge_definitions_code_check check (
    code ~ '^[a-z][a-z0-9_]*$'
    and char_length(code) between 1 and 64
  ),
  constraint badge_definitions_title_check check (
    char_length(btrim(title)) between 1 and 100
  ),
  constraint badge_definitions_description_check check (
    char_length(btrim(description)) between 1 and 500
  ),
  constraint badge_definitions_image_path_check check (
    image_path ~ '^/badges/[a-z0-9-]+\.png$'
  ),
  constraint badge_definitions_category_check check (
    category in (
      'season',
      'league_phase',
      'players_cup',
      'performance',
      'matchday'
    )
  ),
  constraint badge_definitions_sort_order_check check (sort_order > 0),
  constraint badge_definitions_code_award_scope_key
    unique (code, award_scope)
);

comment on table public.badge_definitions is
  'Canonical badge metadata. Readable by authenticated users for profile joins; not a public catalogue. award_scope is generated from repeatable so season vs matchday uniqueness cannot drift from the product flags.';

comment on column public.badge_definitions.award_scope is
  'season for unique-per-season badges, matchday for repeatable round badges. Generated from repeatable; referenced by badge_awards.';

comment on column public.badge_definitions.image_path is
  'Public path to the original PNG under /badges/. Optimization to WebP belongs to the profile UI phase.';

create table public.badge_awards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    constraint badge_awards_user_id_fkey
    references public.profiles (id) on delete cascade,
  badge_code text not null,
  award_scope text not null,
  season_label text not null default 'Champions League 2026/27',
  earned_at timestamptz not null default now(),
  matchday_id bigint
    constraint badge_awards_matchday_id_fkey
    references public.matchdays (id) on delete restrict,
  cup_id bigint
    constraint badge_awards_cup_id_fkey
    references public.cup_competitions (id) on delete set null,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint badge_awards_badge_definition_scope_fkey
    foreign key (badge_code, award_scope)
    references public.badge_definitions (code, award_scope),
  constraint badge_awards_award_scope_check check (
    award_scope in ('season', 'matchday')
  ),
  constraint badge_awards_season_label_check check (
    char_length(btrim(season_label)) between 1 and 100
  ),
  constraint badge_awards_matchday_required_check check (
    (award_scope = 'matchday' and matchday_id is not null)
    or award_scope = 'season'
  ),
  constraint badge_awards_context_object_check check (
    jsonb_typeof(context) = 'object'
  )
);

comment on table public.badge_awards is
  'Earned badge instances. Empty after this migration. Future award engines write rows; authenticated users may only read them. Unique-per-season badges use award_scope = season; repeatable round badges use award_scope = matchday with a required matchday_id.';

comment on column public.badge_awards.award_scope is
  'Must match badge_definitions.award_scope via the composite foreign key. Enables partial unique indexes without a trigger.';

comment on column public.badge_awards.season_label is
  'Season identity for unique badges. No seasons table in this milestone. Current default is Champions League 2026/27.';

comment on column public.badge_awards.matchday_id is
  'Required for matchday-scoped awards. bigint, matching public.matchdays.id. ON DELETE RESTRICT because SET NULL would break the matchday-scope NOT NULL check.';

comment on column public.badge_awards.cup_id is
  'Optional context for Players Cup badges. Those badges remain unique per season; cup_id is not part of uniqueness.';

comment on column public.badge_awards.context is
  'Display/support metadata only. Core award truth is the typed columns, not this JSON.';

-- Unique-per-season badges: one row per player, badge and season.
create unique index badge_awards_user_season_uidx
  on public.badge_awards (user_id, badge_code, season_label)
  where award_scope = 'season';

-- Repeatable matchday badges: one row per player, badge and UEFA round.
create unique index badge_awards_user_matchday_uidx
  on public.badge_awards (user_id, badge_code, matchday_id)
  where award_scope = 'matchday';

create index badge_awards_user_id_idx
  on public.badge_awards (user_id);

create index badge_awards_badge_code_idx
  on public.badge_awards (badge_code);

create index badge_awards_matchday_id_idx
  on public.badge_awards (matchday_id);

create index badge_awards_cup_id_idx
  on public.badge_awards (cup_id);

create index badge_awards_season_label_idx
  on public.badge_awards (season_label);

insert into public.badge_definitions (
  code,
  title,
  description,
  image_path,
  repeatable,
  category,
  sort_order
)
values
  (
    'exact_machine',
    'Exact Machine',
    'Πέτυχες 10 ακριβή σκορ συνολικά.',
    '/badges/exact-machine.png',
    false,
    'performance',
    40
  ),
  (
    'sharp_shooter',
    'Sharp Shooter',
    'Πέτυχες 3 ακριβή σκορ στην ίδια αγωνιστική.',
    '/badges/sharp-shooter.png',
    true,
    'performance',
    41
  ),
  (
    'on_fire',
    'On Fire',
    'Συγκέντρωσες 20 ή περισσότερους βαθμούς σε μία αγωνιστική.',
    '/badges/on-fire.png',
    true,
    'performance',
    42
  ),
  (
    'top_of_the_matchday',
    'Top of the Matchday',
    'Τερμάτισες στην 1η θέση μιας αγωνιστικής.',
    '/badges/top-of-the-matchday.png',
    true,
    'matchday',
    43
  ),
  (
    'second_of_the_matchday',
    'Second of the Matchday',
    'Τερμάτισες στη 2η θέση μιας αγωνιστικής.',
    '/badges/second-of-the-matchday.png',
    true,
    'matchday',
    44
  ),
  (
    'third_of_the_matchday',
    'Third of the Matchday',
    'Τερμάτισες στην 3η θέση μιας αγωνιστικής.',
    '/badges/third-of-the-matchday.png',
    true,
    'matchday',
    45
  ),
  (
    'final_boss',
    'Final Boss',
    'Πέτυχες το ακριβές σκορ του Τελικού.',
    '/badges/final-boss.png',
    false,
    'performance',
    46
  ),
  (
    'perfect_matchday',
    'Perfect Matchday',
    'Πέτυχες τουλάχιστον το σωστό αποτέλεσμα σε όλους τους αγώνες μιας αγωνιστικής.',
    '/badges/perfect-matchday.png',
    true,
    'matchday',
    47
  ),
  (
    'leader',
    'Leader',
    'Βρέθηκες στην 1η θέση της γενικής κατάταξης.',
    '/badges/leader.png',
    false,
    'performance',
    48
  ),
  (
    'league_phase_champion',
    'League Phase Champion',
    'Τερμάτισες 1ος μετά την ολοκλήρωση της League Phase.',
    '/badges/league-phase-champion.png',
    false,
    'league_phase',
    20
  ),
  (
    'league_phase_runner_up',
    'League Phase Runner-up',
    'Τερμάτισες 2ος μετά την ολοκλήρωση της League Phase.',
    '/badges/league-phase-runner-up.png',
    false,
    'league_phase',
    21
  ),
  (
    'season_champion',
    'Season Champion',
    'Κατέκτησες την 1η θέση στη γενική κατάταξη της σεζόν.',
    '/badges/season-champion.png',
    false,
    'season',
    1
  ),
  (
    'season_runner_up',
    'Season Runner-up',
    'Τερμάτισες 2ος στη γενική κατάταξη της σεζόν.',
    '/badges/season-runner-up.png',
    false,
    'season',
    2
  ),
  (
    'season_top_5',
    'Season Top 5',
    'Τερμάτισες από την 3η έως την 5η θέση στη γενική κατάταξη της σεζόν.',
    '/badges/season-top-5.png',
    false,
    'season',
    3
  ),
  (
    'players_cup_champion',
    'Players Cup Champion',
    'Κατέκτησες το Players Cup.',
    '/badges/players-cup-champion.png',
    false,
    'players_cup',
    30
  ),
  (
    'players_cup_finalist',
    'Players Cup Finalist',
    'Έφτασες στον Τελικό του Players Cup.',
    '/badges/players-cup-finalist.png',
    false,
    'players_cup',
    31
  ),
  (
    'players_cup_semifinalist',
    'Players Cup Semifinalist',
    'Έφτασες στα Ημιτελικά του Players Cup.',
    '/badges/players-cup-semifinalist.png',
    false,
    'players_cup',
    32
  )
on conflict (code) do update
set
  title = excluded.title,
  description = excluded.description,
  image_path = excluded.image_path,
  repeatable = excluded.repeatable,
  category = excluded.category,
  sort_order = excluded.sort_order;

alter table public.badge_definitions enable row level security;
alter table public.badge_awards enable row level security;

-- Read-only for players, matching cup_awards. No insert, update or delete
-- policy exists, so the Data API rejects every browser write before column
-- grants are considered.
create policy "Authenticated users can view badge definitions"
  on public.badge_definitions
  for select
  to authenticated
  using (true);

create policy "Authenticated users can view badge awards"
  on public.badge_awards
  for select
  to authenticated
  using (true);

revoke all privileges on table public.badge_definitions
  from public, anon, authenticated;
revoke all privileges on table public.badge_awards
  from public, anon, authenticated;

grant select on table public.badge_definitions to authenticated;
grant select on table public.badge_awards to authenticated;

grant all privileges on table public.badge_definitions to service_role;
grant all privileges on table public.badge_awards to service_role;
