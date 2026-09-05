# English Supabase clean bootstrap

**NEVER apply these files to Greek production.**

- Greek edition: `www.thescoreclub.gr`, hosted project `aoprkdbqtibsnlusbbpz`
- English edition: `the-score-club.com`, a **new** separate Supabase project (not created yet)

This directory is **outside** `supabase/migrations/`. The CLI will not pick it
up during `supabase db push` or `supabase db reset`. That is intentional.

## Safety guards

- NEVER apply `english-bootstrap/` to Greek hosted Supabase.
- NEVER copy Greek `auth.users`, profiles, predictions, Cup state, badge awards,
  or push rows.
- NEVER replay documentary migrations:
  - `20260829173000_prelaunch_game_data_backup_20260829.sql`
  - `20260829174500_official_2026_27_league_phase_import.sql`
- NEVER use unscoped `supabase db push`.
- When the English project exists, always pass an **explicit English**
  `--project-ref`.
- This repo is currently CLI-linked to Greek project `aoprkdbqtibsnlusbbpz`.
  Unscoped `supabase db push` / `db reset` against that link is forbidden.
- Do not deploy Edge Functions from this preparation step.

## Apply order (empty English database only)

1. `0001_schema.sql` — tables, views, functions, triggers, RLS, grants, RPCs
2. `0002_official_seed.sql` — 36 teams, 8 English matchdays, 144 scheduled fixtures
3. `0003_english_badges.sql` — 17 English `badge_definitions` (no awards)
4. `0004_feedback_messages.sql` — player contact inbox (table, RLS, RPCs). Apply this to the **existing** English production project; do not `db push` Greek migration history. Also apply after 0001–0003 on any future empty English bootstrap.
5. `verify.sql` — read-only post-seed checks

`assemble.py` rebuilds `0001` and `0002` from classified `supabase/migrations`
files. It does not connect to any hosted project.

`local_auth_stub.sql` is only for a throwaway local Postgres that has no Auth
schema. Do not apply it to hosted Greek or English Supabase.

## What stays empty

No configuration row is required for Players Cup. The Cup schema, RPCs, and
default reward columns (50 / 30 / 15) are created in `0001`. A competition row
is created later by an English admin calling `create_players_cup`.

These tables/views of user state must remain empty after bootstrap:

- `auth.users`
- `profiles`
- `predictions`
- `golden_match_selections`
- `long_term_predictions`
- `long_term_outcomes`
- `long_term_awards`
- `badge_awards`
- `cup_competitions`
- `cup_participants`
- `cup_rounds`
- `cup_ties`
- `cup_awards`
- `cup_excluded_matches`
- `push_subscriptions`
- `push_broadcasts`
- `feedback_messages`

## Admin creation (future English project only)

Do **not** copy the Greek admin Auth row.

1. Register a brand-new user on the English project through the English app.
2. Confirm `handle_new_user` created `public.profiles` for that user.
3. Promote that profile only:

```sql
update public.profiles
set role = 'admin'
where username = '<english-admin-username>'
  and status = 'active';
```

4. Verify `is_admin()` as that user before scoring or broadcasting.

## Edge Function later

`supabase/functions/send-broadcast-push` has no Greek project ref or URL
hardcoded. It can be deployed unchanged to English Supabase later if given:

- English `SUPABASE_URL`
- English `SUPABASE_SERVICE_ROLE_KEY`
- English `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` (and matching public VAPID in the English app env)

Do not deploy it during this preparation.

## Local `db reset` warning

`supabase db reset` still applies `supabase/migrations/`, including the two
unsafe Greek documentary files. Do not use reset as an English bootstrap path.

## Migration classification (`supabase/migrations`)

### A — Safe schema/logic (included in `0001`)

- `20260809205123_baseline_current_schema.sql`
- `20260809205214_harden_prediction_points_and_function_access.sql`
- `20260811080542_admin_result_scoring.sql`
- `20260811081143_qualify_scoring_admin_check.sql`
- `20260811090456_league_phase_standings.sql`
- `20260811213426_golden_match.sql`
- `20260811213819_golden_match_fk_index.sql`
- `20260813161331_long_term_predictions.sql`
- `20260813161540_qualify_long_term_prediction_conflict.sql`
- `20260813161632_qualify_long_term_outcome_conflicts.sql`
- `20260813162111_long_term_outcomes_decided_by_index.sql`
- `20260818191500_fix_long_term_prediction_locking.sql`
- `20260819101500_push_notifications.sql`
- `20260819145500_players_cup_bracket.sql`
- `20260820095100_players_cup_phase_2a.sql`
- `20260820110500_players_cup_phase_2b.sql`
- `20260820183000_players_cup_reward_values.sql`
- `20260821141500_knockout_final_scoring.sql`
- `20260827194500_badges_matchday_engine.sql`
- `20260828100000_badges_ranking_engine.sql`
- `20260828120000_badges_backfill_recovery.sql`
- `20260828140000_leader_first_matchday_guard.sql`
- `20260829160000_profiles_username_format.sql`
- `20260829190000_predictions_require_active_profile.sql`
- `20260901120000_matchday_leaderboard.sql`

### Additive after 0001 (do not concatenate into 0001)

- `20260906120000_feedback_messages.sql` — apply as `0004_feedback_messages.sql` to English production / empty bootstraps. Never `db push` this Greek migration history into English.

### D — Needs manual review (schema taken, Greek seed replaced)

- `20260827190000_badges_foundation.sql` — tables/RLS/grants are in `0001`;
  the 17 Greek `badge_definitions` INSERTs are omitted and replaced by
  `0003_english_badges.sql`.

### C — Greek production / documentary / unsafe to replay (excluded)

- `20260829173000_prelaunch_game_data_backup_20260829.sql` — CTAS of live tables
  into `prelaunch_backup_20260829`
- `20260829174500_official_2026_27_league_phase_import.sql` — destructive swap
  (DELETE predictions/matches/teams) plus Greek matchday names

There is no class B standalone static seed in `migrations/` besides the badge
INSERT inside the D file. Official 2026/27 data for English is `0002`.
