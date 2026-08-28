-- Transactional Badges backfill / recovery verification.
-- Every fixture mutation is rolled back. Do not run against hosted Supabase.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function pg_temp.bf_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $helper$
begin
  if p_condition is distinct from true then
    raise exception 'BADGES BACKFILL TEST FAILED: %', p_message;
  end if;
end;
$helper$;

create function pg_temp.bf_user_id(p_index integer)
returns uuid
language sql
immutable
as $helper$
  select ('00000000-0000-4000-8000-' || lpad((9940 + p_index)::text, 12, '0'))::uuid;
$helper$;

create function pg_temp.bf_add_player(p_index integer)
returns uuid
language plpgsql
as $helper$
declare
  v_user_id uuid := pg_temp.bf_user_id(p_index);
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id,
    'badges-backfill-' || lpad(p_index::text, 3, '0') || '@example.invalid',
    jsonb_build_object('username', 'zzbfill' || lpad(p_index::text, 3, '0'))
  );
  return v_user_id;
end;
$helper$;

create function pg_temp.bf_add_matchday(p_stage text, p_min_number integer default 1)
returns bigint
language plpgsql
as $helper$
declare
  v_number integer;
  v_id bigint;
begin
  select greatest(coalesce(max(matchday.matchday_number), 0) + 1, p_min_number)
  into v_number
  from public.matchdays as matchday
  where matchday.stage = p_stage;

  insert into public.matchdays (stage, matchday_number, name)
  values (
    p_stage,
    v_number,
    'zz-badge-bfill-' || p_stage || '-' || v_number::text
  )
  returning id into v_id;

  return v_id;
end;
$helper$;

create function pg_temp.bf_add_match(p_matchday_id bigint, p_kickoff timestamptz)
returns bigint
language plpgsql
as $helper$
declare
  v_id bigint;
begin
  insert into public.matches (
    matchday_id,
    home_team_id,
    away_team_id,
    kickoff_at,
    status
  )
  values (
    p_matchday_id,
    current_setting('test.team_home')::bigint,
    current_setting('test.team_away')::bigint,
    p_kickoff,
    'scheduled'
  )
  returning id into v_id;

  return v_id;
end;
$helper$;

create function pg_temp.bf_predict(
  p_index integer,
  p_match_id bigint,
  p_home integer,
  p_away integer
)
returns void
language sql
as $helper$
  insert into public.predictions (
    user_id,
    match_id,
    predicted_home_score,
    predicted_away_score
  )
  values (
    pg_temp.bf_user_id(p_index),
    p_match_id,
    p_home,
    p_away
  )
  on conflict (user_id, match_id) do update
  set
    predicted_home_score = excluded.predicted_home_score,
    predicted_away_score = excluded.predicted_away_score,
    points = null,
    updated_at = now();
$helper$;

create function pg_temp.bf_award_count(
  p_index integer,
  p_code text,
  p_matchday_id bigint default null
)
returns bigint
language sql
stable
as $helper$
  select count(*)
  from public.badge_awards as award
  where award.user_id = pg_temp.bf_user_id(p_index)
    and award.badge_code = p_code
    and (
      p_matchday_id is null
      or award.matchday_id = p_matchday_id
    );
$helper$;

create function pg_temp.bf_earned_at(
  p_index integer,
  p_code text,
  p_matchday_id bigint default null
)
returns timestamptz
language sql
stable
as $helper$
  select award.earned_at
  from public.badge_awards as award
  where award.user_id = pg_temp.bf_user_id(p_index)
    and award.badge_code = p_code
    and (
      p_matchday_id is null
      or award.matchday_id = p_matchday_id
    );
$helper$;

create function pg_temp.bf_source(p_signature text)
returns text
language sql
stable
as $helper$
  select pg_get_functiondef(p_signature::regprocedure);
$helper$;

create function pg_temp.bf_score(p_match_id bigint, p_home integer, p_away integer)
returns void
language plpgsql
as $helper$
begin
  perform set_config('request.jwt.claim.sub', pg_temp.bf_user_id(1)::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.set_match_result(p_match_id, p_home, p_away);
end;
$helper$;

create function pg_temp.bf_recompute()
returns jsonb
language plpgsql
as $helper$
declare
  v_summary jsonb;
begin
  v_summary := public.recompute_all_badges();
  perform set_config('test.summary', v_summary::text, true);
  return v_summary;
end;
$helper$;

create function pg_temp.bf_finish_preexisting_all()
returns void
language plpgsql
as $helper$
begin
  update public.matches as match_row
  set
    status = 'finished',
    home_score = coalesce(match_row.home_score, 0),
    away_score = coalesce(match_row.away_score, 0),
    updated_at = now()
  where match_row.id in (
    select preexisting.id from pg_temp.bf_preexisting_matches as preexisting
  )
    and match_row.status is distinct from 'finished';

  update public.predictions as prediction
  set
    points = 0,
    updated_at = now()
  where prediction.match_id in (
    select preexisting.id from pg_temp.bf_preexisting_matches as preexisting
  )
    and prediction.points is null;
end;
$helper$;

create function pg_temp.bf_ensure_cup(p_completed boolean)
returns bigint
language plpgsql
as $helper$
declare
  v_cup_id bigint;
  v_index integer;
  v_rank integer;
begin
  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = 'players-cup-2026-27';

  if v_cup_id is null then
    insert into public.cup_competitions (
      slug,
      season_label,
      participant_count,
      status,
      winner_points,
      finalist_points,
      semi_finalist_points
    )
    values (
      'players-cup-2026-27',
      'Champions League 2026/27',
      8,
      case when p_completed then 'completed' else 'active' end,
      50,
      30,
      15
    )
    returning id into v_cup_id;

    for v_index in 2..9 loop
      insert into public.cup_participants (
        cup_id,
        user_id,
        username_snapshot,
        rank_position,
        bracket_position,
        entry_round
      )
      values (
        v_cup_id,
        pg_temp.bf_user_id(v_index),
        'zzbfill' || lpad(v_index::text, 3, '0'),
        v_index - 1,
        v_index - 1,
        1
      );
    end loop;
  else
    update public.cup_competitions
    set
      status = case when p_completed then 'completed' else 'active' end,
      updated_at = now()
    where id = v_cup_id;

    for v_index in 2..9 loop
      if not exists (
        select 1
        from public.cup_participants as participant
        where participant.cup_id = v_cup_id
          and participant.user_id = pg_temp.bf_user_id(v_index)
      ) then
        select min(slot.n)
        into v_rank
        from generate_series(1, 64) as slot(n)
        where not exists (
          select 1
          from public.cup_participants as participant
          where participant.cup_id = v_cup_id
            and participant.rank_position = slot.n
        )
        and not exists (
          select 1
          from public.cup_participants as participant
          where participant.cup_id = v_cup_id
            and participant.bracket_position = slot.n
        );

        if v_rank is not null then
          insert into public.cup_participants (
            cup_id,
            user_id,
            username_snapshot,
            rank_position,
            bracket_position,
            entry_round
          )
          values (
            v_cup_id,
            pg_temp.bf_user_id(v_index),
            'zzbfill' || lpad(v_index::text, 3, '0'),
            v_rank,
            v_rank,
            1
          );
        end if;
      end if;
    end loop;
  end if;

  return v_cup_id;
end;
$helper$;

create function pg_temp.bf_set_cup_award(
  p_cup_id bigint,
  p_index integer,
  p_type text,
  p_points integer
)
returns void
language plpgsql
as $helper$
declare
  v_participant_id bigint;
begin
  select participant.id
  into v_participant_id
  from public.cup_participants as participant
  where participant.cup_id = p_cup_id
    and participant.user_id = pg_temp.bf_user_id(p_index);

  if v_participant_id is null then
    raise exception 'BADGES BACKFILL TEST FAILED: no cup participant for index %', p_index;
  end if;

  insert into public.cup_awards (
    cup_id,
    participant_id,
    user_id,
    award_type,
    points
  )
  values (
    p_cup_id,
    v_participant_id,
    pg_temp.bf_user_id(p_index),
    p_type,
    p_points
  )
  on conflict (cup_id, participant_id) do update
  set
    user_id = excluded.user_id,
    award_type = excluded.award_type,
    points = excluded.points,
    updated_at = now();
end;
$helper$;

create table pg_temp.bf_preexisting_matches (
  id bigint primary key
);

insert into pg_temp.bf_preexisting_matches (id)
select match_row.id
from public.matches as match_row;

-- ---------------------------------------------------------------------------
-- Fixture people and teams
-- ---------------------------------------------------------------------------

select pg_temp.bf_add_player(1);
select pg_temp.bf_add_player(2);
select pg_temp.bf_add_player(3);
select pg_temp.bf_add_player(4);
select pg_temp.bf_add_player(5);
select pg_temp.bf_add_player(6);
select pg_temp.bf_add_player(7);
select pg_temp.bf_add_player(8);
select pg_temp.bf_add_player(9);
select pg_temp.bf_add_player(10);

update public.profiles as profile
set role = 'admin'
where profile.id = pg_temp.bf_user_id(1);

update public.profiles as profile
set status = 'disabled'
where profile.status = 'active'
  and profile.id not in (
    select pg_temp.bf_user_id(index.n)
    from generate_series(1, 10) as index(n)
  );

insert into public.teams (name, short_name)
values
  ('ZZ Badge Bfill Home', 'ZBH'),
  ('ZZ Badge Bfill Away', 'ZBA');

select set_config(
  'test.team_home',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Bfill Home'
  ),
  true
);
select set_config(
  'test.team_away',
  (
    select team.id::text
    from public.teams as team
    where team.name = 'ZZ Badge Bfill Away'
  ),
  true
);

select pg_temp.bf_finish_preexisting_all();

delete from public.long_term_awards;
delete from public.long_term_outcomes;
delete from public.badge_awards;

-- Unique #1 before any master recompute so a tied-at-zero board cannot
-- insert Leader for every active fixture user.
select set_config('test.lead_md', pg_temp.bf_add_matchday('playoff')::text, true);
select set_config(
  'test.lead_m',
  pg_temp.bf_add_match(
    current_setting('test.lead_md')::bigint,
    now() + interval '40 days'
  )::text,
  true
);
select pg_temp.bf_predict(2, current_setting('test.lead_m')::bigint, 2, 1);
select pg_temp.bf_score(current_setting('test.lead_m')::bigint, 2, 1);

-- ---------------------------------------------------------------------------
-- E. Matchday walk (empty ignored, incomplete cleared, populated processed)
-- ---------------------------------------------------------------------------

select set_config('test.empty_md', pg_temp.bf_add_matchday('playoff')::text, true);

select set_config('test.inc_md', pg_temp.bf_add_matchday('playoff')::text, true);
select set_config(
  'test.inc_m1',
  pg_temp.bf_add_match(
    current_setting('test.inc_md')::bigint,
    now() + interval '41 days'
  )::text,
  true
);
select set_config(
  'test.inc_m2',
  pg_temp.bf_add_match(
    current_setting('test.inc_md')::bigint,
    now() + interval '41 days 1 hour'
  )::text,
  true
);

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  season_label,
  matchday_id,
  context
)
values (
  pg_temp.bf_user_id(4),
  'sharp_shooter',
  'matchday',
  'Champions League 2026/27',
  current_setting('test.inc_md')::bigint,
  jsonb_build_object('exact_count', 3)
);

select set_config(
  'test.walk_distinct',
  (
    select count(distinct match_row.matchday_id)::text
    from public.matches as match_row
  ),
  true
);

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  public.badge_matchday_is_complete(current_setting('test.inc_md')::bigint) = false
  and pg_temp.bf_award_count(
    4,
    'sharp_shooter',
    current_setting('test.inc_md')::bigint
  ) = 0
  and not exists (
    select 1
    from public.matches as match_row
    where match_row.matchday_id = current_setting('test.empty_md')::bigint
  )
  and (current_setting('test.summary')::jsonb ->> 'matchdays_processed')::integer
    = current_setting('test.walk_distinct')::integer
  and (current_setting('test.summary')::jsonb ->> 'matchdays_processed')::integer
    = (
      select count(distinct match_row.matchday_id)::integer
      from public.matches as match_row
    )
  and (current_setting('test.summary')::jsonb ->> 'complete_matchdays')::integer
    = (
      select count(*)::integer
      from (
        select distinct match_row.matchday_id
        from public.matches as match_row
        where public.badge_matchday_is_complete(match_row.matchday_id)
      ) as complete_round
    )
  and current_setting('test.empty_md')::bigint
    <> all (
      select distinct match_row.matchday_id
      from public.matches as match_row
    ),
  'empty matchday ignored; incomplete populated matchday processed and stale awards cleared'
);

delete from public.predictions
where match_id in (
  current_setting('test.inc_m1')::bigint,
  current_setting('test.inc_m2')::bigint
);
delete from public.matches
where id in (
  current_setting('test.inc_m1')::bigint,
  current_setting('test.inc_m2')::bigint
);

-- ---------------------------------------------------------------------------
-- Full persisted world for backfill (scored via canonical set_match_result)
-- ---------------------------------------------------------------------------

select set_config('test.lp_md', pg_temp.bf_add_matchday('league_phase')::text, true);

create table pg_temp.bf_lp_matches (
  ord integer primary key,
  id bigint not null
);

insert into pg_temp.bf_lp_matches (ord, id)
select
  slot.n,
  pg_temp.bf_add_match(
    current_setting('test.lp_md')::bigint,
    now() + interval '42 days' + (slot.n || ' hours')::interval
  )
from generate_series(1, 10) as slot(n);

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  pg_temp.bf_user_id(2),
  lp_match.id,
  2,
  1
from pg_temp.bf_lp_matches as lp_match;

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  pg_temp.bf_user_id(3),
  lp_match.id,
  2,
  1
from pg_temp.bf_lp_matches as lp_match
where lp_match.ord <= 3;

insert into public.predictions (
  user_id,
  match_id,
  predicted_home_score,
  predicted_away_score
)
select
  pg_temp.bf_user_id(4),
  lp_match.id,
  2,
  1
from pg_temp.bf_lp_matches as lp_match
where lp_match.ord = 1;

do $score$
declare
  v_id bigint;
begin
  for v_id in
    select lp_match.id
    from pg_temp.bf_lp_matches as lp_match
    order by lp_match.ord
  loop
    perform pg_temp.bf_score(v_id, 2, 1);
  end loop;
end;
$score$;

select set_config('test.final_md', pg_temp.bf_add_matchday('final')::text, true);
select set_config(
  'test.final_m',
  pg_temp.bf_add_match(
    current_setting('test.final_md')::bigint,
    now() + interval '43 days'
  )::text,
  true
);
select pg_temp.bf_predict(2, current_setting('test.final_m')::bigint, 2, 1);
select pg_temp.bf_predict(3, current_setting('test.final_m')::bigint, 1, 0);
select pg_temp.bf_score(current_setting('test.final_m')::bigint, 2, 1);

select set_config('test.cup_id', pg_temp.bf_ensure_cup(true)::text, true);
delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint;
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 6, 'winner', 50
);
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 7, 'finalist', 30
);
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 8, 'semi_finalist', 15
);
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 9, 'semi_finalist', 15
);

insert into public.long_term_predictions (user_id, prediction_type, team_id)
values
  (pg_temp.bf_user_id(2), 'league_phase_first', current_setting('test.team_home')::bigint),
  (pg_temp.bf_user_id(2), 'winner', current_setting('test.team_home')::bigint);

insert into public.long_term_outcomes (prediction_type, team_id, decided_by)
values
  (
    'league_phase_first',
    current_setting('test.team_home')::bigint,
    pg_temp.bf_user_id(1)
  ),
  (
    'winner',
    current_setting('test.team_home')::bigint,
    pg_temp.bf_user_id(1)
  );

insert into public.long_term_awards (
  user_id,
  prediction_type,
  predicted_team_id,
  outcome_team_id,
  points
)
values
  (
    pg_temp.bf_user_id(2),
    'league_phase_first',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    15
  ),
  (
    pg_temp.bf_user_id(2),
    'winner',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    30
  );

select pg_temp.bf_assert(
  public.badge_league_phase_is_complete() = true
  and public.badge_season_is_complete() = true,
  'canonical LP and season gates pass on the full fixture'
);

-- ---------------------------------------------------------------------------
-- A. Full backfill from empty awards (plus a persisted non-#1 Leader)
-- ---------------------------------------------------------------------------

delete from public.badge_awards;

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  season_label,
  context
)
values (
  pg_temp.bf_user_id(5),
  'leader',
  'season',
  'Champions League 2026/27',
  jsonb_build_object('rank', 1, 'source', 'historical')
);

select pg_temp.bf_assert(
  (select count(*) from public.badge_awards) = 1
  and pg_temp.bf_award_count(5, 'leader') = 1,
  'backfill starts from empty awards plus one persisted Leader'
);

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  (current_setting('test.summary')::jsonb ? 'matchdays_processed')
  and (current_setting('test.summary')::jsonb ? 'complete_matchdays')
  and (current_setting('test.summary')::jsonb ? 'award_count_before')
  and (current_setting('test.summary')::jsonb ? 'award_count_after')
  and (current_setting('test.summary')::jsonb ? 'leader_count')
  and (current_setting('test.summary')::jsonb ? 'recomputed_at')
  and not (current_setting('test.summary')::jsonb ? 'user_id')
  and not (current_setting('test.summary')::jsonb ? 'username')
  and (current_setting('test.summary')::jsonb ->> 'award_count_before')::bigint = 1
  and (current_setting('test.summary')::jsonb ->> 'award_count_after')::bigint
    = (select count(*) from public.badge_awards)
  and (current_setting('test.summary')::jsonb ->> 'matchdays_processed')::integer
    = (
      select count(distinct match_row.matchday_id)::integer
      from public.matches as match_row
    )
  and (current_setting('test.summary')::jsonb ->> 'complete_matchdays')::integer
    = (current_setting('test.summary')::jsonb ->> 'matchdays_processed')::integer,
  'summary shape is diagnostic, has no private user fields, and walks only populated matchdays'
);

select pg_temp.bf_assert(
  pg_temp.bf_award_count(
    2, 'sharp_shooter', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(
    3, 'sharp_shooter', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(
    4, 'sharp_shooter', current_setting('test.lp_md')::bigint
  ) = 0
  and pg_temp.bf_award_count(
    2, 'on_fire', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(
    2, 'perfect_matchday', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(
    2, 'top_of_the_matchday', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(
    3, 'second_of_the_matchday', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(
    4, 'third_of_the_matchday', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(2, 'exact_machine') = 1
  and pg_temp.bf_award_count(2, 'final_boss') = 1,
  'matchday and cumulative badges backfill from persisted scores'
);

select pg_temp.bf_assert(
  exists (
    select 1
    from public.badge_league_phase_ranking() as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'league_phase_champion'
    where standing.rank_position = 1
  )
  and exists (
    select 1
    from public.badge_league_phase_ranking() as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'league_phase_runner_up'
    where standing.rank_position = 2
  )
  and not exists (
    select 1
    from public.badge_awards as award
    where award.badge_code = 'league_phase_champion'
      and not exists (
        select 1
        from public.badge_league_phase_ranking() as standing
        where standing.user_id = award.user_id
          and standing.rank_position = 1
      )
  )
  and not exists (
    select 1
    from public.badge_awards as award
    where award.badge_code = 'league_phase_runner_up'
      and not exists (
        select 1
        from public.badge_league_phase_ranking() as standing
        where standing.user_id = award.user_id
          and standing.rank_position = 2
      )
  ),
  'LP badges follow canonical ranking helpers'
);

select pg_temp.bf_assert(
  exists (
    select 1
    from public.badge_season_ranking_for('{}'::uuid[]) as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'season_champion'
    where standing.rank_position = 1
  )
  and exists (
    select 1
    from public.badge_season_ranking_for('{}'::uuid[]) as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'season_runner_up'
    where standing.rank_position = 2
  )
  and not exists (
    select 1
    from public.badge_awards as award
    where award.badge_code = 'season_top_5'
      and not exists (
        select 1
        from public.badge_season_ranking_for('{}'::uuid[]) as standing
        where standing.user_id = award.user_id
          and standing.rank_position in (3, 4, 5)
      )
  )
  and (
    select count(distinct standing.user_id)
    from public.badge_season_ranking_for('{}'::uuid[]) as standing
    where standing.rank_position in (3, 4, 5)
  ) = (
    select count(*)
    from public.badge_awards as award
    where award.badge_code = 'season_top_5'
  ),
  'season badges follow canonical ranking helpers'
);

select pg_temp.bf_assert(
  pg_temp.bf_award_count(6, 'players_cup_champion') = 1
  and pg_temp.bf_award_count(6, 'players_cup_finalist') = 0
  and pg_temp.bf_award_count(7, 'players_cup_finalist') = 1
  and pg_temp.bf_award_count(8, 'players_cup_semifinalist') = 1
  and pg_temp.bf_award_count(9, 'players_cup_semifinalist') = 1
  and pg_temp.bf_award_count(2, 'players_cup_champion') = 0,
  'Cup badges mirror persisted cup_awards'
);

select pg_temp.bf_assert(
  exists (
    select 1
    from public.get_leaderboard() as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'leader'
    where standing.rank_position = 1
      and standing.user_id = pg_temp.bf_user_id(2)
  )
  and (
    select count(*)
    from public.get_leaderboard() as standing
    where standing.rank_position = 1
  ) = 1
  and pg_temp.bf_award_count(2, 'leader') = 1
  and pg_temp.bf_award_count(5, 'leader') = 1
  and pg_temp.bf_award_count(10, 'leader') = 0
  and (
    select standing.rank_position
    from public.get_leaderboard() as standing
    where standing.user_id = pg_temp.bf_user_id(5)
  ) is distinct from 1
  and (
    select standing.rank_position
    from public.get_leaderboard() as standing
    where standing.user_id = pg_temp.bf_user_id(10)
  ) is distinct from 1,
  'current #1 earns Leader; existing non-#1 Leader remains; prior #1 is not fabricated'
);

-- ---------------------------------------------------------------------------
-- B. Idempotency
-- ---------------------------------------------------------------------------

create table pg_temp.bf_award_snapshot (
  id bigint primary key,
  user_id uuid not null,
  badge_code text not null,
  matchday_id bigint,
  earned_at timestamptz not null
);

insert into pg_temp.bf_award_snapshot (
  id, user_id, badge_code, matchday_id, earned_at
)
select award.id, award.user_id, award.badge_code, award.matchday_id, award.earned_at
from public.badge_awards as award;

select set_config(
  'test.award_count',
  (select count(*)::text from public.badge_awards),
  true
);

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  (select count(*) from public.badge_awards)
    = current_setting('test.award_count')::bigint
  and not exists (
    select 1
    from public.badge_awards as award
    group by award.user_id, award.badge_code, award.matchday_id, award.season_label
    having count(*) > 1
  )
  and not exists (
    select 1
    from pg_temp.bf_award_snapshot as snapshot
    where not exists (
      select 1
      from public.badge_awards as award
      where award.id = snapshot.id
        and award.earned_at = snapshot.earned_at
        and award.user_id = snapshot.user_id
        and award.badge_code = snapshot.badge_code
    )
  )
  and (
    select count(*)
    from public.badge_awards as award
    where award.user_id = pg_temp.bf_user_id(2)
      and award.badge_code = 'leader'
  ) = 1
  and (
    select count(*)
    from public.badge_awards as award
    where award.badge_code = 'leader'
      and award.user_id = pg_temp.bf_user_id(5)
  ) = 1,
  'second recompute keeps rows, earned_at, and a single Leader per holder'
);

-- ---------------------------------------------------------------------------
-- C. Stale award recovery
-- ---------------------------------------------------------------------------

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  season_label,
  matchday_id,
  context
)
values (
  pg_temp.bf_user_id(4),
  'sharp_shooter',
  'matchday',
  'Champions League 2026/27',
  current_setting('test.lp_md')::bigint,
  jsonb_build_object('exact_count', 3)
);

insert into public.badge_awards (
  user_id,
  badge_code,
  award_scope,
  season_label,
  context
)
values (
  pg_temp.bf_user_id(4),
  'exact_machine',
  'season',
  'Champions League 2026/27',
  jsonb_build_object('exact_count', 10)
);

update public.badge_awards
set
  badge_code = 'top_of_the_matchday',
  context = jsonb_build_object('rank', 1, 'stale', true)
where user_id = pg_temp.bf_user_id(4)
  and badge_code = 'third_of_the_matchday'
  and matchday_id = current_setting('test.lp_md')::bigint;

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  pg_temp.bf_award_count(
    4, 'sharp_shooter', current_setting('test.lp_md')::bigint
  ) = 0
  and pg_temp.bf_award_count(4, 'exact_machine') = 0
  and pg_temp.bf_award_count(
    4, 'top_of_the_matchday', current_setting('test.lp_md')::bigint
  ) = 0
  and pg_temp.bf_award_count(
    4, 'third_of_the_matchday', current_setting('test.lp_md')::bigint
  ) = 1
  and pg_temp.bf_award_count(5, 'leader') = 1,
  'stale recomputable awards are removed and the valid podium replacement is inserted; Leader stays'
);

-- ---------------------------------------------------------------------------
-- D. Shared current #1
-- ---------------------------------------------------------------------------

insert into public.long_term_awards (
  user_id,
  prediction_type,
  predicted_team_id,
  outcome_team_id,
  points
)
values
  (
    pg_temp.bf_user_id(8),
    'winner',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    5000
  ),
  (
    pg_temp.bf_user_id(9),
    'winner',
    current_setting('test.team_home')::bigint,
    current_setting('test.team_home')::bigint,
    5000
  );

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  (
    select count(*)
    from public.get_leaderboard() as standing
    where standing.rank_position = 1
      and standing.user_id in (pg_temp.bf_user_id(8), pg_temp.bf_user_id(9))
  ) = 2
  and pg_temp.bf_award_count(8, 'leader') = 1
  and pg_temp.bf_award_count(9, 'leader') = 1
  and pg_temp.bf_award_count(2, 'leader') = 1
  and pg_temp.bf_award_count(5, 'leader') = 1
  and pg_temp.bf_award_count(10, 'leader') = 0,
  'shared current #1 all earn Leader; previous holders are never revoked'
);

delete from public.long_term_awards
where user_id in (pg_temp.bf_user_id(8), pg_temp.bf_user_id(9))
  and prediction_type = 'winner';

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  pg_temp.bf_award_count(8, 'leader') = 1
  and pg_temp.bf_award_count(9, 'leader') = 1
  and pg_temp.bf_award_count(2, 'leader') = 1,
  'falling off shared #1 does not remove Leader'
);

-- ---------------------------------------------------------------------------
-- F. Cup mirror correction
-- ---------------------------------------------------------------------------

delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint;

select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 2, 'winner', 50
);
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 3, 'finalist', 30
);

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  pg_temp.bf_award_count(6, 'players_cup_champion') = 0
  and pg_temp.bf_award_count(7, 'players_cup_finalist') = 0
  and pg_temp.bf_award_count(8, 'players_cup_semifinalist') = 0
  and pg_temp.bf_award_count(2, 'players_cup_champion') = 1
  and pg_temp.bf_award_count(3, 'players_cup_finalist') = 1
  and pg_temp.bf_award_count(2, 'players_cup_finalist') = 0,
  'cup_awards changes recompute to the new Cup badge mapping'
);

delete from public.cup_awards
where cup_id = current_setting('test.cup_id')::bigint;
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 6, 'winner', 50
);
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 7, 'finalist', 30
);
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 8, 'semi_finalist', 15
);
select pg_temp.bf_set_cup_award(
  current_setting('test.cup_id')::bigint, 9, 'semi_finalist', 15
);
select pg_temp.bf_recompute();

-- ---------------------------------------------------------------------------
-- G. LP / season gates through existing helpers
-- ---------------------------------------------------------------------------

select set_config(
  'test.gap_m',
  pg_temp.bf_add_match(
    current_setting('test.lp_md')::bigint,
    now() + interval '44 days'
  )::text,
  true
);

select pg_temp.bf_assert(
  public.badge_league_phase_is_complete() = false
  and public.badge_season_is_complete() = false,
  'an unfinished LP match fails both canonical completeness gates'
);

select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  not exists (
    select 1
    from public.badge_awards as award
    where award.badge_code in (
      'league_phase_champion',
      'league_phase_runner_up',
      'season_champion',
      'season_runner_up',
      'season_top_5'
    )
  )
  and pg_temp.bf_award_count(2, 'leader') = 1
  and pg_temp.bf_award_count(5, 'leader') = 1
  and pg_temp.bf_award_count(
    2, 'top_of_the_matchday', current_setting('test.lp_md')::bigint
  ) = 0
  and pg_temp.bf_award_count(2, 'exact_machine') = 1,
  'incomplete gates clear LP/season and that matchday; Leader and Exact Machine remain'
);

select pg_temp.bf_score(current_setting('test.gap_m')::bigint, 2, 1);
select pg_temp.bf_recompute();

select pg_temp.bf_assert(
  public.badge_league_phase_is_complete() = true
  and public.badge_season_is_complete() = true
  and exists (
    select 1
    from public.badge_league_phase_ranking() as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'league_phase_champion'
    where standing.rank_position = 1
  )
  and exists (
    select 1
    from public.badge_season_ranking_for('{}'::uuid[]) as standing
    join public.badge_awards as award
      on award.user_id = standing.user_id
      and award.badge_code = 'season_champion'
    where standing.rank_position = 1
  )
  and pg_temp.bf_award_count(
    2, 'top_of_the_matchday', current_setting('test.lp_md')::bigint
  ) = 1,
  'completing the gap restores LP/season through canonical helpers'
);

-- ---------------------------------------------------------------------------
-- H. Admin security
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claim.sub', pg_temp.bf_user_id(2)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
begin
  begin
    perform public.admin_recompute_badges();
    raise exception 'BADGES BACKFILL TEST FAILED: non-admin executed admin_recompute_badges';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'Active administrator privileges are required' then
        raise;
      end if;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_all_badges();
    raise exception 'BADGES BACKFILL TEST FAILED: authenticated executed recompute_all_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;

update public.profiles
set status = 'disabled'
where id = pg_temp.bf_user_id(1);

select set_config('request.jwt.claim.sub', pg_temp.bf_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $test$
begin
  begin
    perform public.admin_recompute_badges();
    raise exception 'BADGES BACKFILL TEST FAILED: inactive admin executed admin_recompute_badges';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'Active administrator privileges are required' then
        raise;
      end if;
  end;
end;
$test$;

reset role;

update public.profiles
set status = 'active'
where id = pg_temp.bf_user_id(1);

select set_config('request.jwt.claim.sub', pg_temp.bf_user_id(1)::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select set_config(
  'test.admin_summary',
  (public.admin_recompute_badges())::text,
  true
);
reset role;

select pg_temp.bf_assert(
  (current_setting('test.admin_summary')::jsonb ? 'recomputed_at')
  and (current_setting('test.admin_summary')::jsonb ->> 'matchdays_processed')::integer
    > 0,
  'active admin can execute admin_recompute_badges'
);

set local role anon;

do $test$
begin
  begin
    perform public.admin_recompute_badges();
    raise exception 'BADGES BACKFILL TEST FAILED: anon executed admin_recompute_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

do $test$
begin
  begin
    perform public.recompute_all_badges();
    raise exception 'BADGES BACKFILL TEST FAILED: anon executed recompute_all_badges';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$test$;

reset role;

-- ---------------------------------------------------------------------------
-- I. Phase 1-3 body / scoring regressions
-- ---------------------------------------------------------------------------

select pg_temp.bf_assert(
  position(
    'recompute_matchday_badges' in pg_temp.bf_source('public.recompute_all_badges()')
  ) > 0
  and position(
    'recompute_cumulative_badges' in pg_temp.bf_source('public.recompute_all_badges()')
  ) > 0
  and position(
    'recompute_ranking_badges' in pg_temp.bf_source('public.recompute_all_badges()')
  ) > 0
  and position(
    'recompute_matchday_badges' in pg_temp.bf_source('public.recompute_all_badges()')
  ) < position(
    'recompute_cumulative_badges' in pg_temp.bf_source('public.recompute_all_badges()')
  )
  and position(
    'recompute_cumulative_badges' in pg_temp.bf_source('public.recompute_all_badges()')
  ) < position(
    'recompute_ranking_badges' in pg_temp.bf_source('public.recompute_all_badges()')
  )
  and position(
    'players_cup_apply' in pg_temp.bf_source('public.recompute_all_badges()')
  ) = 0
  and position(
    'distinct match_row.matchday_id' in pg_temp.bf_source('public.recompute_all_badges()')
  ) > 0,
  'master recompute walks populated matchdays then cumulative then ranking'
);

select pg_temp.bf_assert(
  position(
    'recompute_all_badges' in pg_temp.bf_source('public.admin_recompute_badges()')
  ) > 0
  and position(
    'Active administrator privileges are required'
      in pg_temp.bf_source('public.admin_recompute_badges()')
  ) > 0,
  'admin wrapper reuses the internal master recompute'
);

select pg_temp.bf_assert(
  position(
    'players_cup_apply'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'recompute_matchday_badges'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'recompute_cumulative_badges'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'recompute_ranking_badges'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'players_cup_apply'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) < position(
    'recompute_matchday_badges'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  )
  and position(
    'when v_stage = ''final'' then 10'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'when v_stage = ''final'' then 4'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'when selection.id is not null then 10'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0
  and position(
    'when selection.id is not null then 4'
      in pg_temp.bf_source('public.set_match_result(bigint, integer, integer)')
  ) > 0,
  'set_match_result keeps Cup then Phase 2 badges then ranking; Final/GM 10/4 remain'
);

select pg_temp.bf_assert(
  position(
    'do nothing'
      in pg_temp.bf_source('public.award_leader_if_applicable()')
  ) > 0
  and position(
    'delete'
      in pg_temp.bf_source('public.award_leader_if_applicable()')
  ) = 0
  and position(
    'award_leader_if_applicable'
      in pg_temp.bf_source('public.recompute_ranking_badges()')
  ) > 0
  and position(
    'recompute_league_phase_badges'
      in pg_temp.bf_source('public.recompute_ranking_badges()')
  ) > 0
  and position(
    'recompute_season_badges'
      in pg_temp.bf_source('public.recompute_ranking_badges()')
  ) > 0
  and position(
    'sync_players_cup_badges'
      in pg_temp.bf_source('public.recompute_ranking_badges()')
  ) > 0
  and position(
    'recompute_matchday_badges'
      in pg_temp.bf_source('public.recompute_ranking_badges()')
  ) = 0,
  'Leader stays insert-only; ranking orchestrator is unchanged'
);

select pg_temp.bf_assert(
  position(
    'recompute_ranking_badges'
      in pg_temp.bf_source('public.set_long_term_outcome(text, bigint)')
  ) > 0
  and position(
    'players_cup_apply'
      in pg_temp.bf_source('public.recompute_players_cup()')
  ) > 0
  and position(
    'recompute_ranking_badges'
      in pg_temp.bf_source('public.recompute_players_cup()')
  ) > 0
  and position(
    'players_cup_apply'
      in pg_temp.bf_source('public.recompute_players_cup()')
  ) < position(
    'recompute_ranking_badges'
      in pg_temp.bf_source('public.recompute_players_cup()')
  )
  and position(
    'recompute_ranking_badges'
      in pg_temp.bf_source('public.players_cup_apply(bigint)')
  ) = 0
  and position(
    'sync_players_cup_badges'
      in pg_temp.bf_source('public.players_cup_apply(bigint)')
  ) = 0,
  'long-term and Cup write paths still sync ranking badges after persisted awards'
);

select pg_temp.bf_assert(
  (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = pg_temp.bf_user_id(2)
      and prediction.match_id = (
        select lp_match.id
        from pg_temp.bf_lp_matches as lp_match
        where lp_match.ord = 1
      )
  ) = 5
  and (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = pg_temp.bf_user_id(2)
      and prediction.match_id = current_setting('test.final_m')::bigint
  ) = 10
  and (
    select prediction.points
    from public.predictions as prediction
    where prediction.user_id = pg_temp.bf_user_id(3)
      and prediction.match_id = current_setting('test.final_m')::bigint
  ) = 4,
  'scoring remains 5 for a league-phase exact and 10/4 for Final'
);

reset role;
rollback;

do $test$
begin
  if exists (
    select 1
    from public.profiles as profile
    where profile.username like 'zzbfill%'
  ) then
    raise exception 'BADGES BACKFILL TEST FAILED: the fixture left data behind';
  end if;
end;
$test$;

select unnest(array[
  'matchday_walk_empty_incomplete',
  'full_backfill_from_empty_awards',
  'idempotent_second_recompute',
  'stale_award_recovery',
  'leader_current_shared_persist_no_fabricate',
  'cup_mirror_and_correction',
  'lp_season_canonical_gates',
  'admin_security',
  'phase_1_2_3_bodies_and_scoring',
  'all_fixture_changes_rolled_back'
]) as passed_test;
