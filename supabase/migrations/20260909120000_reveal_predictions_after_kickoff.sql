-- Reveal other players' match predictions after kickoff.
--
-- Owner rows stay visible to the owner at all times via the existing
-- SELECT policy. Other players' rows become readable only when
-- now() >= matches.kickoff_at. Write policies, scoring, Golden Match
-- selection logic, long-term predictions, and existing grants are unchanged.
--
-- Do not db push from this file. Do not repair migration history.
-- Apply to hosted Supabase only after review.

-- ---------------------------------------------------------------------------
-- Predictions: authenticated users may read a row after kickoff.
-- Disabled owners remain readable only to themselves (existing owner policy)
-- and to admins (existing admin policy).
-- ---------------------------------------------------------------------------

drop policy if exists "Users can view predictions after kickoff"
  on public.predictions;
create policy "Users can view predictions after kickoff"
  on public.predictions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.matches as match_row
      where match_row.id = public.predictions.match_id
        and now() >= match_row.kickoff_at
    )
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = public.predictions.user_id
        and profile.status = 'active'
    )
  );

-- ---------------------------------------------------------------------------
-- Golden Match: the selection must not leak before kickoff.
-- After kickoff it may be shown next to the revealed prediction.
-- ---------------------------------------------------------------------------

drop policy if exists "Users can view Golden Match selections after kickoff"
  on public.golden_match_selections;
create policy "Users can view Golden Match selections after kickoff"
  on public.golden_match_selections
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.matches as match_row
      where match_row.id = public.golden_match_selections.match_id
        and now() >= match_row.kickoff_at
    )
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = public.golden_match_selections.user_id
        and profile.status = 'active'
    )
  );

-- ---------------------------------------------------------------------------
-- Batch read for the Predictions page. One call per selected matchday,
-- not one call per match card. SECURITY INVOKER keeps RLS as the boundary.
-- The kickoff filter is applied again so upcoming matches return no rows
-- even if a caller passes their ids.
-- ---------------------------------------------------------------------------

create or replace function public.get_match_player_predictions(
  p_match_ids bigint[]
)
returns table (
  match_id bigint,
  user_id uuid,
  username text,
  predicted_home_score integer,
  predicted_away_score integer,
  points integer,
  is_golden_match boolean
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select
    prediction.match_id,
    prediction.user_id,
    profile.username,
    prediction.predicted_home_score,
    prediction.predicted_away_score,
    prediction.points,
    exists (
      select 1
      from public.golden_match_selections as golden
      where golden.user_id = prediction.user_id
        and golden.match_id = prediction.match_id
    ) as is_golden_match
  from public.predictions as prediction
  inner join public.profiles as profile
    on profile.id = prediction.user_id
   and profile.status = 'active'
  inner join public.matches as match_row
    on match_row.id = prediction.match_id
  where p_match_ids is not null
    and prediction.match_id = any (p_match_ids)
    and now() >= match_row.kickoff_at
  order by
    prediction.match_id,
    profile.username;
$function$;

comment on function public.get_match_player_predictions(bigint[])
is 'Batch-read active players'' match predictions after kickoff. SECURITY INVOKER: RLS still hides other users'' rows before kickoff. Does not change scoring or Golden Match writes.';

revoke execute on function public.get_match_player_predictions(bigint[])
  from public, anon;
grant execute on function public.get_match_player_predictions(bigint[])
  to authenticated, service_role;
