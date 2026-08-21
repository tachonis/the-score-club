-- Players Cup published awards: 50 / 30 / 15.
-- Additive only. Does not rewrite historical Phase 1 / 2A / 2B migrations.
-- Rebases create_players_cup on the current hosted function body. The only
-- intentional behavioural change is the published reward constants.
-- Existing competition rows are not updated; hosted currently has none.

alter table public.cup_competitions
  alter column winner_points set default 50,
  alter column finalist_points set default 30,
  alter column semi_finalist_points set default 15;

create or replace function public.create_players_cup(
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  c_slug constant text := 'players-cup-2026-27';
  c_season_label constant text := 'Champions League 2026/27';
  c_bracket_size constant integer := 64;
  c_minimum_participants constant integer := 8;
  c_protected_seed_count constant integer := 8;
  -- Initial reward configuration. Once the row exists it is the only source of
  -- truth; award calculation must never read these constants.
  c_winner_points constant integer := 50;
  c_finalist_points constant integer := 30;
  c_semi_finalist_points constant integer := 15;

  v_admin_id uuid := (select auth.uid());
  v_cup_id bigint;
  v_summary jsonb;
  v_ranking jsonb;
  v_participants jsonb;
  -- One draw seed per call. A dry run returns it as a preview seed and throws
  -- it away; a real creation persists it alongside the bracket it produced.
  v_draw_seed uuid := gen_random_uuid();
  v_draw jsonb;
  v_preview jsonb;
  v_eligible_count integer;
  v_participant_count integer;
  v_matchday_count integer;
  v_ranking_match_count integer;
  v_ranking_finished_count integer;
begin
  if v_admin_id is null
    or not exists (
      select 1
      from public.profiles as profile
      where profile.id = v_admin_id
        and profile.role = 'admin'
        and profile.status = 'active'
    )
  then
    raise exception using
      errcode = '42501',
      message = 'Active administrator privileges are required';
  end if;

  -- Serializes concurrent creation attempts. The lock is released at commit or
  -- rollback, so two simultaneous callers converge on one competition instead
  -- of racing on the unique slug.
  perform pg_advisory_xact_lock(
    hashtext('public.create_players_cup:' || c_slug)::bigint
  );

  select competition.id
  into v_cup_id
  from public.cup_competitions as competition
  where competition.slug = c_slug
  for update;

  -- The Cup is never regenerated. An existing bracket is reported back
  -- untouched, for a dry run and for a normal call alike.
  if v_cup_id is not null then
    select jsonb_build_object(
      'already_exists', true,
      'created', false,
      'dry_run', p_dry_run,
      'cup_id', competition.id,
      'slug', competition.slug,
      'season_label', competition.season_label,
      'status', competition.status,
      'bracket_size', competition.bracket_size,
      'protected_seed_count', c_protected_seed_count,
      'participant_count', competition.participant_count,
      'draw_seed', competition.draw_seed,
      'draw_is_preview', false,
      'created_at', competition.created_at,
      'rewards', jsonb_build_object(
        'winner_points', competition.winner_points,
        'finalist_points', competition.finalist_points,
        'semi_finalist_points', competition.semi_finalist_points
      ),
      'round_count', (
        select count(*)
        from public.cup_rounds as round
        where round.cup_id = competition.id
      ),
      'tie_count', (
        select count(*)
        from public.cup_ties as tie
        where tie.cup_id = competition.id
      )
    )
    into v_summary
    from public.cup_competitions as competition
    where competition.id = v_cup_id;

    return v_summary;
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  if v_matchday_count <> 6 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 3 to 8 must all exist before the Players Cup can be created';
  end if;

  select count(*)
  into v_matchday_count
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_matchday_count <> 2 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 are required for a deterministic ranking';
  end if;

  -- Freezes the ranking inputs for the rest of the transaction, so a result
  -- correction cannot land between the preview and the written bracket.
  perform 1
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2
  order by match_row.id
  for share of match_row;

  select
    count(*),
    count(*) filter (where match_row.status = 'finished')
  into v_ranking_match_count, v_ranking_finished_count
  from public.matches as match_row
  join public.matchdays as matchday
    on matchday.id = match_row.matchday_id
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 1 and 2;

  if v_ranking_match_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchdays 1 and 2 have no configured matches';
  end if;

  if v_ranking_finished_count <> v_ranking_match_count then
    raise exception using
      errcode = '22023',
      message = 'The Cup ranking requires every League Phase Matchday 1 and 2 match to be finished';
  end if;

  if exists (
    select 1
    from public.predictions as prediction
    join public.matches as match_row
      on match_row.id = prediction.match_id
    join public.matchdays as matchday
      on matchday.id = match_row.matchday_id
    where matchday.stage = 'league_phase'
      and matchday.matchday_number between 1 and 2
      and prediction.points is null
  ) then
    raise exception using
      errcode = '55000',
      message = 'League Phase Matchday 1 and 2 predictions are not fully scored';
  end if;

  -- Single evaluation of the ranking. Everything below reads this snapshot, so
  -- a registration committed mid-call cannot change the written bracket.
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank_position', ranking.rank_position,
          'user_id', ranking.user_id,
          'username', ranking.username,
          'total_points', ranking.total_points,
          'exact_scores', ranking.exact_scores,
          'correct_results', ranking.correct_results,
          'missed_predictions', ranking.missed_predictions
        )
        order by ranking.rank_position
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  into v_ranking, v_eligible_count
  from public.players_cup_ranking() as ranking;

  if v_eligible_count < c_minimum_participants then
    raise exception using
      errcode = '22023',
      message = format(
        'The Players Cup needs at least %s active players, found %s',
        c_minimum_participants,
        v_eligible_count
      );
  end if;

  v_participant_count := least(v_eligible_count, c_bracket_size);

  select coalesce(
    jsonb_agg(ranked.entry order by (ranked.entry->>'rank_position')::integer),
    '[]'::jsonb
  )
  into v_participants
  from jsonb_array_elements(v_ranking) as ranked(entry)
  where (ranked.entry->>'rank_position')::integer <= v_participant_count;

  -- Drawn once. The preview and the persisted bracket are built from this one
  -- result, so what an admin sees is exactly what gets written.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank_position', placement.rank_position,
        'user_id', placement.user_id,
        'bracket_position', placement.bracket_position,
        'entry_round', placement.entry_round,
        'is_protected_seed', placement.is_protected_seed
      )
      order by placement.rank_position
    ),
    '[]'::jsonb
  )
  into v_draw
  from public.players_cup_draw(v_draw_seed, v_participants) as placement;

  v_preview := jsonb_build_object(
    'already_exists', false,
    'dry_run', p_dry_run,
    'slug', c_slug,
    'season_label', c_season_label,
    'status', 'active',
    'bracket_size', c_bracket_size,
    'protected_seed_count', c_protected_seed_count,
    'minimum_participants', c_minimum_participants,
    'eligible_count', v_eligible_count,
    'participant_count', v_participant_count,
    'excluded_count', v_eligible_count - v_participant_count,
    'draw_seed', v_draw_seed,
    -- A dry run seed is thrown away: two previews before creation may differ,
    -- and only the seed stored by the real creation describes the real bracket.
    'draw_is_preview', p_dry_run,
    'rewards', jsonb_build_object(
      'winner_points', c_winner_points,
      'finalist_points', c_finalist_points,
      'semi_finalist_points', c_semi_finalist_points
    ),
    'participants', v_draw
  );

  if p_dry_run then
    return v_preview || jsonb_build_object(
      'created', false,
      'cup_id', null::bigint
    );
  end if;

  insert into public.cup_competitions (
    slug,
    season_label,
    bracket_size,
    participant_count,
    status,
    draw_seed,
    winner_points,
    finalist_points,
    semi_finalist_points,
    created_by
  )
  values (
    c_slug,
    c_season_label,
    c_bracket_size,
    v_participant_count,
    'active',
    v_draw_seed,
    c_winner_points,
    c_finalist_points,
    c_semi_finalist_points,
    v_admin_id
  )
  returning cup_competitions.id into v_cup_id;

  insert into public.cup_participants (
    cup_id,
    user_id,
    username_snapshot,
    rank_position,
    bracket_position,
    entry_round
  )
  select
    v_cup_id,
    (drawn.entry->>'user_id')::uuid,
    ranked.entry->>'username',
    (drawn.entry->>'rank_position')::integer,
    (drawn.entry->>'bracket_position')::integer,
    (drawn.entry->>'entry_round')::integer
  from jsonb_array_elements(v_draw) as drawn(entry)
  join jsonb_array_elements(v_ranking) as ranked(entry)
    on (ranked.entry->>'rank_position')::integer
      = (drawn.entry->>'rank_position')::integer;

  insert into public.cup_rounds (
    cup_id,
    round_number,
    slot_count,
    matchday_id,
    status
  )
  select
    v_cup_id,
    matchday.matchday_number - 2,
    case matchday.matchday_number
      when 3 then 64
      when 4 then 32
      when 5 then 16
      when 6 then 8
      when 7 then 4
      else 2
    end,
    matchday.id,
    'pending'
  from public.matchdays as matchday
  where matchday.stage = 'league_phase'
    and matchday.matchday_number between 3 and 8;

  -- The whole skeleton exists from creation: 32+16+8+4+2+1 ties. Progression
  -- will only ever update these rows.
  insert into public.cup_ties (cup_id, round_id, slot, outcome)
  select v_cup_id, round.id, slot_series.slot, 'empty'
  from public.cup_rounds as round
  cross join lateral generate_series(1, round.slot_count / 2) as slot_series(slot)
  where round.cup_id = v_cup_id;

  with pairing as (
    select
      ((slot_template.fold_position + 1) / 2)::integer as slot,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 1) as home_bracket_position,
      max(slot_template.bracket_position)
        filter (where slot_template.fold_position % 2 = 0) as away_bracket_position
    from public.players_cup_bracket_slots(c_bracket_size) as slot_template
    group by ((slot_template.fold_position + 1) / 2)
  ),
  resolved as (
    select
      pairing.slot,
      home_participant.id as home_participant_id,
      away_participant.id as away_participant_id
    from pairing
    left join public.cup_participants as home_participant
      on home_participant.cup_id = v_cup_id
      and home_participant.bracket_position = pairing.home_bracket_position
    left join public.cup_participants as away_participant
      on away_participant.cup_id = v_cup_id
      and away_participant.bracket_position = pairing.away_bracket_position
  )
  update public.cup_ties as tie
  set
    home_participant_id = resolved.home_participant_id,
    away_participant_id = resolved.away_participant_id,
    winner_participant_id = case
      when resolved.home_participant_id is null
        then resolved.away_participant_id
      when resolved.away_participant_id is null
        then resolved.home_participant_id
      else null
    end,
    outcome = case
      when resolved.home_participant_id is null
        and resolved.away_participant_id is null then 'empty'
      when resolved.home_participant_id is null
        or resolved.away_participant_id is null then 'bye'
      else 'pending'
    end,
    updated_at = now()
  from resolved
  join public.cup_rounds as round
    on round.cup_id = v_cup_id
    and round.round_number = 1
  where tie.round_id = round.id
    and tie.slot = resolved.slot;

  return v_preview || jsonb_build_object(
    'created', true,
    'cup_id', v_cup_id
  );
end;
$function$;

comment on function public.create_players_cup(boolean)
is 'Admin-only Players Cup creation. Freezes the Matchday 1-2 ranking, protects the top 8, draws everyone else inside their entry-round group from a persisted draw_seed, writes the full six round and 63 tie skeleton, and never regenerates an existing Cup. Scoring, progression and awards are out of scope. New competitions use the published 50/30/15 reward defaults unless the row is later reconfigured.';

comment on column public.cup_competitions.winner_points is
  'Published default 50. Award calculation always reads this row, never hardcoded literals.';

comment on column public.cup_competitions.finalist_points is
  'Published default 30. Award calculation always reads this row, never hardcoded literals.';

comment on column public.cup_competitions.semi_finalist_points is
  'Published default 15. Award calculation always reads this row, never hardcoded literals.';

revoke execute on function public.create_players_cup(boolean)
  from public, anon;
grant execute on function public.create_players_cup(boolean)
  to authenticated, service_role;
