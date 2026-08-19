# Supabase database

The `migrations` directory is the versioned source of truth for The Score Club
database schema.

The baseline migration records the schema that existed in the hosted Supabase
project before migration tracking was introduced. The following hardening
migration narrows Data API grants, protects `predictions.points`, restricts
privileged function execution, and adds the missing match-team indexes. The
result-scoring migrations add the admin-only `set_match_result` RPC, remove
direct Data API writes to match result columns, and implement deterministic
normal scoring with safe result correction. The League Phase standings
migration adds an authenticated-only `security_invoker` view that derives all
36 team rows from finished League Phase matches. The Golden Match migrations
add one server-owned selection per user and matchday, the guarded
`set_golden_match` RPC, and deterministic 10/4/0 scoring while preserving the
normal 5/2/0 path. The Long-term Predictions migrations add separate player
selections, admin-owned outcomes, server-owned awards, Matchday 3 locking,
deterministic 30/15/0 recomputation, and the leaderboard aggregate without
writing long-term points into `predictions.points`.

All eleven migrations have already been applied to Supabase project
`aoprkdbqtibsnlusbbpz`. They contain no seed data and do not delete existing
rows.

The transactional SQL fixtures in `tests/golden_match.sql` and
`tests/long_term_predictions.sql` validate scoring, correction, idempotence,
locking, privilege bypass rejection, and rollback all test changes.

Future database changes must be added as new migrations. Do not edit an applied
migration in place.
