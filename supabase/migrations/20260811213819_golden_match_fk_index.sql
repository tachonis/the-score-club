create index golden_match_selections_match_matchday_idx
  on public.golden_match_selections (match_id, matchday_id);

drop index if exists public.golden_match_selections_match_id_idx;
