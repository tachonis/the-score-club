# Fixture-change runbook

Practical production steps for kickoff changes, postponements, cancellations, and result corrections in The Score Club.

This document describes **current behaviour**. It is not a redesign. There is no in-app fixture editor. Kickoff and status changes are done in the **Supabase SQL Editor**. Match results are entered in the **Admin page** (or the same scoring function from SQL).

Do **not** run `db push`. Do **not** apply migrations for a fixture change. Do **not** recreate match rows. Do **not** change match IDs.

---

## How to use this document

1. Find the match (see [Find the match](#find-the-match)).
2. Read the matching scenario below.
3. Copy the SQL template. Replace `MATCH_ID` (and times) before running.
4. Always run the **SELECT** first. Only then run the **UPDATE**. Then run the **post-update SELECT**.
5. If the match is on League Phase Matchdays 3–8, also follow [Players Cup](#players-cup).
6. If a score changes, always finish with `set_match_result` — never edit prediction points by hand.

All kickoff values in the database are **UTC** (`timestamptz`). Convert from Greece time before writing. Do not store local Greece clocks in the database.

---

## What the database already supports

Each match (`public.matches`) has:

| Field | Role |
| --- | --- |
| `id` | Permanent match identity. Never change it. Never recreate the row. |
| `matchday_id` | Which round the match belongs to. Do **not** move Cup matches (Matchdays 3–8) to another matchday. |
| `kickoff_at` | Official kickoff. This **is** the prediction lock time. |
| `status` | `scheduled`, `live`, `finished`, `postponed`, or `cancelled`. |
| `home_score` / `away_score` | Result. Written only by the scoring function, not by the Admin page’s table editor (there isn’t one). |

`live` exists in the schema and Admin labels, but the app **never sets it**. Do not use `live` for operations unless you have a specific reason; it locks predictions the same way as any non-`scheduled` status.

Matchday `starts_at` / `ends_at` are labels for humans. They are **not** used to lock predictions. `matchdays.status` is **not maintained** by the app.

---

## Hard safety rules

> **Warning**
>
> Breaking these rules can silently unlock predictions, lock Golden Match, skip Cup freeze, or leave stale points on the leaderboard.

- **Never delete predictions** because a kickoff moved. Saved scores stay.
- **Never edit `predictions.points` by hand.** Use `set_match_result` (or the un-finish procedure below, which *clears* points to null, then rescores).
- **Never change a finished result without `set_match_result`.** That function rescores predictions, updates the Players Cup if needed, and rebuilds badges.
- **Never move a kickoff into the past** without checking who already saved. A past kickoff **locks immediately**.
- **Never change match IDs** for a rescheduled fixture. Update the existing row.
- **Never recreate a match row** if an update is enough. New IDs orphan predictions and Golden Match selections (those cascade-delete if you delete the old row).
- **Never delete a match row.** Predictions and Golden Match selections on that match are deleted with it.
- **Never use `db push`** for operational fixture changes.
- **Never apply a migration** to change one kickoff.
- **Never finish a Cup match with a raw `UPDATE` of `status` / scores.** Always use `set_match_result`, which freezes postponed Cup exclusions *before* the result is written.
- **Never move `matchday_id`** for a League Phase Matchday 3–8 fixture once the Players Cup exists. The database will reject it.

---

## How prediction locking works

A player can create or update a prediction **only if all** of these are true:

- their account is **active**
- they own the row
- the match `status` is **`scheduled`**
- current time is **before** `kickoff_at`

So:

- Changing `kickoff_at` while the match stays `scheduled` **moves the lock**.
- Setting `postponed`, `cancelled`, `live`, or `finished` **locks immediately**, even if kickoff is still in the future.
- After kickoff, putting a later kickoff back on a still-`scheduled` match **unlocks** predictions again.

The Admin page cannot change kickoff or status. It only calls `set_match_result` with the two scores.

---

## Find the match

```sql
-- Find by teams and round. Copy the id from the result.
select
  match_row.id,
  matchday.name,
  matchday.stage,
  matchday.matchday_number,
  home_team.name as home,
  away_team.name as away,
  match_row.kickoff_at,
  match_row.status,
  match_row.home_score,
  match_row.away_score
from public.matches as match_row
join public.matchdays as matchday
  on matchday.id = match_row.matchday_id
join public.teams as home_team
  on home_team.id = match_row.home_team_id
join public.teams as away_team
  on away_team.id = match_row.away_team_id
where home_team.name = 'HOME TEAM NAME'
  and away_team.name = 'AWAY TEAM NAME'
order by match_row.kickoff_at;
```

Use that `id` as `MATCH_ID` below. Never run a bulk update “for all matches on this date”.

---

## Scenario playbooks

### 1. Kickoff changed before the original kickoff

Official time moved; match is still in the future.

| Question | Answer |
| --- | --- |
| What changes | `matches.kickoff_at` only. Keep `status = 'scheduled'`. |
| Predictions remain valid? | Yes. Do not delete them. |
| Lock moves with new kickoff? | Yes. |
| Existing predictions stored? | Yes. Players may still edit until the **new** kickoff. |
| Golden Match | Stays on the same match. Lock follows the new kickoff (see [Golden Match](#golden-match)). |
| Cup | Still the same round. If this is the **first kickoff of the next League Phase matchday**, you also move the previous Cup round’s cutoff — see [Players Cup](#players-cup). |
| Rescoring | No. |
| Badges / rankings | No, unless a result already exists (it should not). |
| Matchday window | Recalculate `starts_at` / `ends_at` if this match is now the earliest or latest in the round. |

Use [SQL A](#a-change-kickoff-timedate). Then [matchday window](#matchday-windows).

---

### 2. Match moved to another date

Same as scenario 1 if the new date is known and the match will still be played in the **same matchday**.

> **Warning**
>
> Do not change `matchday_id` to “move” a fixture into another round. For Cup matchdays the database blocks this. For other rounds it would attach predictions to the wrong round.

If UEFA keeps it in the same matchday: update `kickoff_at`, keep the same `id` and `matchday_id`.

If the new date is unknown: treat as [scenario 3](#3-match-postponed--new-date-unknown).

---

### 3. Match postponed — new date unknown

| Question | Answer |
| --- | --- |
| What changes | `status = 'postponed'`. Leave `kickoff_at` as the last official time until UEFA publishes a new one. Leave scores null. |
| Predictions remain valid? | Yes. They stay stored. Players **cannot** edit while status is not `scheduled`. |
| Lock | Locked now (because of status), not because of kickoff. |
| Golden Match | Selection **stays** on this match. Players **cannot** switch away while status is not `scheduled`. |
| Cup | Not excluded until the round cutoff passes (first kickoff of the **next** League Phase matchday). Then it is excluded from Cup scoring. Season points can still be added later. |
| Rescoring | No, until a result is entered. |
| Badges | Matchday badges wait until **every** match in that round is `finished`. A postponed match blocks that. |
| Long-term | Unaffected, except Matchday 3: long-term picks stay **open** until every MD3 match is `finished`. |

Use [SQL B](#b-mark-postponed). If this is a Cup matchday, after cutoff see [Players Cup](#players-cup).

---

### 4. Match postponed — new date known

Two steps:

1. If it is not already `postponed`, you may set that first, or go straight to restore.
2. Restore with [SQL C](#c-restore-a-postponed-match-with-a-new-kickoff): `status = 'scheduled'` and the new `kickoff_at`.

| Question | Answer |
| --- | --- |
| Predictions | Kept. If the new kickoff is still in the future, players **can edit again**. |
| Golden Match | Stays attached. If restored as `scheduled` with a future kickoff, the selection **unlocks** and the player may change it. |
| Cup | If the new kickoff is **before** the next matchday’s first kickoff, the match can still count in the Cup when finished. If the new kickoff is **on or after** that cutoff, it is excluded from Cup even if it later finishes. |
| Matchday window | Recalculate. |

> **Warning**
>
> Restoring to `scheduled` with a future kickoff re-opens prediction edits and Golden Match changes. That is current product behaviour, not a bug. If UEFA only delayed the same locked fixture and you do **not** want a new edit window, keep `status = 'postponed'` until you are ready to receive the result, then enter the result with `set_match_result` (which sets `finished`).

---

### 5. Match cancelled

| Question | Answer |
| --- | --- |
| What changes | `status = 'cancelled'`. Leave scores null. Keep the row. |
| Predictions | Kept. Not editable. Points stay empty. |
| Lock | Locked (status). |
| Golden Match | Stays attached. Cannot switch. Doubling never applies unless you later finish the match (do not finish a cancelled match). |
| Cup | Treated as unfinished. After cutoff it is excluded from that Cup round. |
| Season table / missed picks | Cancelled matches are **not** counted as missed. They are also **not** scored. |
| Badges | A cancelled match is not `finished`, so **matchday badges for that round never complete** until this is resolved (see [Open operational risks](#open-operational-risks)). |
| Matchday window | Optional; the cancelled kickoff can stay in the window or you can recompute from remaining scheduled/finished matches. Prefer leaving the window until UEFA is final. |

Use [SQL D](#d-mark-cancelled).

Do **not** delete the match.

---

### 6. Match already started or finished — official correction announced

**Wrong score, match still counted as played:** do **not** un-finish. Use [Result correction](#result-correction). `set_match_result` is safe to run again.

**UEFA says it did not count / was postponed after we already entered a result:** this is the dangerous path. The leaderboard sums stored prediction points even if you later set the match back to `postponed`. You must clear points. Use [SQL F](#f-re-open-a-match-only-if-an-official-correction-requires-it) then follow postponement or a new result.

**Match in progress:** the app has no “live” workflow. Leave it `scheduled` until you have the official 90-minute score, then enter the result. Predictions are already locked once kickoff has passed.

---

### 7. Admin entered the wrong score

Use [Result correction](#result-correction). Do not touch `predictions.points`.

---

### 8. Golden Match selected on a match whose kickoff changes

See [Golden Match](#golden-match). Short version:

- Kickoff **later**, still `scheduled` → selection stays; lock moves later (player may still change until the new kickoff).
- Kickoff **earlier**, still `scheduled` → lock may hit immediately; player may lose remaining edit time.
- Status `postponed` / `cancelled` → selection stays; player cannot switch.

Do **not** delete Golden Match rows by hand.

---

### 9. Players Cup round includes a postponed or cancelled match

See [Players Cup](#players-cup). Short version:

- Same round, still finishes before the next matchday’s first kickoff → still counts in Cup.
- Still unfinished when that cutoff hits → excluded from Cup **forever** for that round. Later season points still count.
- Cup Final (Matchday 8) has **no** cutoff; the Final waits.

---

### 10. Long-term predictions

Long-term Winner / League Phase First lock when **every Matchday 3 match is `finished`**. They do **not** lock on individual kickoffs.

| Fixture change | Effect on long-term |
| --- | --- |
| Kickoff move on MD1, 2, 4–8, knockout | None. |
| Kickoff move on MD3 | None, until results are entered. |
| Postponed / cancelled MD3 match | Long-term stays **open** until that match is `finished` (or you have another ops decision). |
| Result correction on any match | Does not by itself lock or unlock long-term. |

Do not touch long-term tables for a fixture change.

---

## SQL playbook

Run in the Supabase **SQL Editor**. Replace `MATCH_ID`. Run statements in order. Do not wrap unrelated matches in the same update.

### A. Change kickoff time/date

```sql
-- 1. Verify
select
  id,
  matchday_id,
  kickoff_at,
  status,
  home_score,
  away_score
from public.matches
where id = MATCH_ID;

-- 2. Update only this row (example: 21:00 Europe/Athens on 10 Sep 2026 → 18:00 UTC)
update public.matches
set
  kickoff_at = timestamptz '2026-09-10 18:00:00+00',
  updated_at = now()
where id = MATCH_ID
  and status = 'scheduled';

-- 3. Confirm
select
  id,
  kickoff_at,
  status
from public.matches
where id = MATCH_ID;
```

If the `UPDATE` reports 0 rows, the match was not `scheduled`. Stop and inspect.

Then update the matchday window if needed ([below](#matchday-windows)).

---

### B. Mark postponed

```sql
-- 1. Verify
select
  id,
  matchday_id,
  kickoff_at,
  status,
  home_score,
  away_score
from public.matches
where id = MATCH_ID;

-- 2. Postpone only if not already finished
update public.matches
set
  status = 'postponed',
  updated_at = now()
where id = MATCH_ID
  and status in ('scheduled', 'live', 'postponed')
  and home_score is null
  and away_score is null;

-- 3. Confirm
select id, kickoff_at, status, home_score, away_score
from public.matches
where id = MATCH_ID;
```

If the match already has a result, do **not** use this block. Use [SQL F](#f-re-open-a-match-only-if-an-official-correction-requires-it) or [result correction](#result-correction).

If this match is on a Cup round and the next matchday has already started, run **Recalculate Players Cup** on the Admin page (or `select public.recompute_players_cup();`) so the exclusion is frozen.

---

### C. Restore a postponed match with a new kickoff

```sql
-- 1. Verify
select id, matchday_id, kickoff_at, status, home_score, away_score
from public.matches
where id = MATCH_ID;

-- 2. Restore to scheduled with the new official UTC kickoff
update public.matches
set
  status = 'scheduled',
  kickoff_at = timestamptz '2026-09-17 19:00:00+00',
  updated_at = now()
where id = MATCH_ID
  and status = 'postponed'
  and home_score is null
  and away_score is null;

-- 3. Confirm
select id, kickoff_at, status
from public.matches
where id = MATCH_ID;
```

Then [matchday window](#matchday-windows). Read the warning in [scenario 4](#4-match-postponed--new-date-known) about re-opening edits.

---

### D. Mark cancelled

```sql
-- 1. Verify
select id, matchday_id, kickoff_at, status, home_score, away_score
from public.matches
where id = MATCH_ID;

-- 2. Cancel only if there is no stored result
update public.matches
set
  status = 'cancelled',
  updated_at = now()
where id = MATCH_ID
  and status in ('scheduled', 'live', 'postponed')
  and home_score is null
  and away_score is null;

-- 3. Confirm
select id, status, home_score, away_score
from public.matches
where id = MATCH_ID;
```

Do not delete predictions. Do not call `set_match_result` for a cancelled match.

If it is a Cup match and cutoff has passed, recalculate the Players Cup so the exclusion is recorded.

---

### E. Correct a result

Prefer the **Admin page**: open the matchday, type the official 90-minute scores, save. That calls `set_match_result`.

From SQL (same function, same safety):

```sql
-- 1. Verify current row and how many predictions exist
select id, kickoff_at, status, home_score, away_score
from public.matches
where id = MATCH_ID;

select
  count(*) as prediction_count,
  count(*) filter (where points is not null) as scored_count
from public.predictions
where match_id = MATCH_ID;

-- 2. Official 90-minute score only. This finishes the match, rescores
--    predictions, updates Cup + badges in the same transaction.
select *
from public.set_match_result(
  MATCH_ID,   -- p_match_id
  2,          -- p_home_score
  1           -- p_away_score
);

-- 3. Confirm
select id, status, home_score, away_score
from public.matches
where id = MATCH_ID;

select user_id, predicted_home_score, predicted_away_score, points
from public.predictions
where match_id = MATCH_ID
order by user_id;
```

`set_match_result` must be run as an **active admin** session (Admin page) or with equivalent privileges in SQL. It always sets `status = 'finished'`.

---

### F. Re-open a match only if an official correction requires it

Use this **only** when a result was entered and UEFA then says the match is not official (postponed / void). This is not for a wrong score — use [SQL E](#e-correct-a-result) for that.

> **Warning**
>
> If you only set `status` back to `postponed` and leave `predictions.points` filled, those points **remain on the leaderboard**. You must clear points, then rebuild badges and Cup.

```sql
-- 1. Verify
select id, matchday_id, status, home_score, away_score
from public.matches
where id = MATCH_ID;

select id, user_id, points
from public.predictions
where match_id = MATCH_ID;

-- 2. Clear the result (example: back to postponed)
update public.matches
set
  status = 'postponed',
  home_score = null,
  away_score = null,
  updated_at = now()
where id = MATCH_ID;

-- 3. Clear scored points for this match only
update public.predictions
set
  points = null,
  updated_at = now()
where match_id = MATCH_ID;

-- 4. Confirm no leftover scores or points
select id, status, home_score, away_score
from public.matches
where id = MATCH_ID;

select count(*) as still_scored
from public.predictions
where match_id = MATCH_ID
  and points is not null;
```

Then rebuild derived data:

```sql
select public.admin_recompute_badges();
select public.recompute_players_cup();
```

Check the leaderboard in the app and the Players Cup page if the match is on Matchdays 3–8.

---

## Matchday windows

`matchdays.starts_at` and `matchdays.ends_at` are **not** used to lock predictions, Golden Match, Cup cutoff, or badges.

Production convention (official 2026/27 import):

- `starts_at` = earliest kickoff in that matchday
- `ends_at` = latest kickoff **+ 2 hours**

Update them after a kickoff change that alters the first or last match of the round, so the stored window stays honest.

```sql
-- 1. See current window vs actual kickoffs
select
  matchday.id,
  matchday.name,
  matchday.starts_at,
  matchday.ends_at,
  min(match_row.kickoff_at) as first_kickoff,
  max(match_row.kickoff_at) as last_kickoff,
  max(match_row.kickoff_at) + interval '2 hours' as suggested_ends_at
from public.matchdays as matchday
join public.matches as match_row
  on match_row.matchday_id = matchday.id
where matchday.id = (
  select matchday_id from public.matches where id = MATCH_ID
)
group by matchday.id, matchday.name, matchday.starts_at, matchday.ends_at;

-- 2. Write the suggested window onto that matchday only
update public.matchdays as matchday
set
  starts_at = bounds.first_kickoff,
  ends_at = bounds.last_kickoff + interval '2 hours'
from (
  select
    match_row.matchday_id,
    min(match_row.kickoff_at) as first_kickoff,
    max(match_row.kickoff_at) as last_kickoff
  from public.matches as match_row
  where match_row.matchday_id = (
    select matchday_id from public.matches where id = MATCH_ID
  )
  group by match_row.matchday_id
) as bounds
where matchday.id = bounds.matchday_id;

-- 3. Confirm
select id, name, starts_at, ends_at
from public.matchdays
where id = (select matchday_id from public.matches where id = MATCH_ID);
```

> **Warning**
>
> Changing the **earliest** kickoff of League Phase Matchday N also changes the live Players Cup cutoff for Matchday N−1 (until that cutoff is frozen). See below.

---

## Golden Match

Golden Match is League Phase only, from Matchday 2. One selection per user per matchday, stored as `golden_match_selections.match_id`. Lock is **the selected match’s** `status` and `kickoff_at`, not the matchday window.

Scoring: when that match is finished, the player’s prediction on **that same match** is 10 / 4 / 0 instead of 5 / 2 / 0. Final matches use 10 / 4 / 0 from the stage, not Golden Match. The two never stack.

### Kickoff moves later (still scheduled)

- Selection **remains valid**. Do not clear it.
- Lock **moves** with the new kickoff. The player may change Golden Match until the new kickoff (and while status stays `scheduled`).

### Kickoff moves earlier (still scheduled)

- Selection stays.
- If the new kickoff is already in the past, Golden Match **locks now**. The player cannot switch to another match.
- Players who had not selected yet cannot pick this match after the new kickoff.

Before moving a kickoff earlier, check selections:

```sql
select
  selection.user_id,
  profile.username,
  selection.match_id,
  match_row.kickoff_at,
  match_row.status
from public.golden_match_selections as selection
join public.matches as match_row
  on match_row.id = selection.match_id
left join public.profiles as profile
  on profile.id = selection.user_id
where selection.match_id = MATCH_ID;
```

Safe admin procedure: if UEFA only brought the time forward a little and it is still in the future, update `kickoff_at` and tell players the new lock time. If the new time has already passed, expect locked Golden Match and locked predictions.

### Match postponed

- Selection **stays on the same match**. Do not delete it.
- Status is not `scheduled`, so the player **cannot** replace it.
- When the match is later finished, doubling still applies to that match.
- If you restore to `scheduled` with a future kickoff, the player **can** change Golden Match again (current implementation).

### Match cancelled

- Selection stays. Doubling will not apply unless you wrongly finish the match. Leave it cancelled.

Do not invent a “clear Golden Match” admin tool. There isn’t one. Do not delete selection rows unless a future product change says so.

---

## Players Cup

Cup rounds map to League Phase Matchdays 3–8. Players do not write Cup tables. Exclusions are stored in `cup_excluded_matches` (`cutoff_at` = cutoff copied at freeze time, `excluded_at` = when recorded). Frozen exclusions are **never removed**. A late result must not reopen a closed round.

**Cutoff (rounds on MD3–MD7):** first kickoff of the **next** League Phase matchday (`min(kickoff_at)` on that next matchday).  
**Final (MD8):** no cutoff. The Final waits for included matches to finish.

A match is excluded from Cup scoring when:

- it already has a frozen exclusion row, **or**
- cutoff has been reached **and** (the match is not `finished`, **or** its `kickoff_at` is on/after the cutoff)

Excluded matches contribute **0** Cup points. If they later finish, **season** prediction points still count; Cup does not get them retroactively. That matches the in-app Cup rules text.

`set_match_result` on a Cup match **freezes exclusions first**, then writes the result, then rebuilds the bracket. That is why results must go through that function.

There is no “exclude this match” button. Freeze happens via:

- entering a Cup-round result (`set_match_result`), or
- **Recalculate Players Cup** on the Admin page (`recompute_players_cup`)

### One Cup-round fixture postponed past the round cutoff

1. Keep the match row. Set `postponed` ([SQL B](#b-mark-postponed)) if not already.
2. Do **not** enter a fake result to “close” the round.
3. Run **Recalculate Players Cup** so `cup_excluded_matches` records the exclusion while the match is still unfinished.
4. When UEFA later plays it, restore kickoff if needed, then enter the real result with `set_match_result`. Season points update. Cup round stays closed to that match.

### One fixture cancelled

Same as unfinished for Cup: after cutoff it is excluded. Recalculate Players Cup. Do not `set_match_result`.

### Result arrives late (after cutoff)

Use **Admin page / `set_match_result` only**. Freeze runs before finish, so the late result cannot sneak back into the Cup round.

### Rescheduled inside the same Cup round

- New kickoff **before** the next matchday’s first kickoff, and finished in time → still included.
- New kickoff **on or after** that cutoff → excluded even if finished (the kickoff itself proves it was moved past the cutoff).

Do not change `matchday_id` to put the replay in another Cup round.

### First kickoff of the *next* matchday changes

That timestamp **is** the previous round’s Cup cutoff until exclusions are frozen. Moving it later delays exclusion. Moving it earlier can exclude matches sooner. After freeze, the copied `cutoff_at` on exclusion rows does not move.

---

## Result correction

Wrong score entered by admin. Match should stay finished.

1. **Inspect the match**

   ```sql
   select id, matchday_id, status, home_score, away_score, kickoff_at
   from public.matches
   where id = MATCH_ID;
   ```

2. **Correct score and status** via Admin page save, or `set_match_result(MATCH_ID, home, away)`. This sets `finished` and the two scores.

3. **Predictions on that match** are rescored in the same call (`scored_predictions` / `changed_predictions` in the return). You do not pick rows yourself.

4. **Scoring / recompute already inside `set_match_result`:**
   - prediction points for that match
   - Players Cup freeze + full bracket rebuild if the matchday is a Cup round
   - `recompute_matchday_badges` for that matchday
   - `recompute_cumulative_badges`
   - `recompute_ranking_badges` (Leader, League Phase, season, Cup badge sync)

5. **Standings** are not a stored table. Open the leaderboard in the app (`get_leaderboard`). League Phase table is a view over **finished** League Phase matches.

6. **If the match is Matchdays 3–8**, open Players Cup and confirm the round. Optional: Admin page **Recalculate Players Cup**.

7. **Do not** `UPDATE predictions SET points = …`.

Checklist:

- [ ] Verified match id and current scores
- [ ] Official 90-minute score only (no extra time / penalties in this app)
- [ ] Ran `set_match_result` once with the correct scores
- [ ] Return row shows `status = finished` and expected `changed_predictions`
- [ ] Leaderboard spot-check
- [ ] Cup spot-check if Matchdays 3–8
- [ ] Golden Match doubling still on the selected match only (10/4/0 vs 5/2/0)

---

## After-action checks (any scenario)

- [ ] Only one match row changed (`id` unchanged)
- [ ] Predictions for that match still exist
- [ ] If you intended to lock: status is not `scheduled`, **or** now ≥ kickoff
- [ ] If you intended to reopen edits: status is `scheduled` and kickoff is in the future
- [ ] Matchday `starts_at` / `ends_at` updated when first/last kickoff changed
- [ ] Cup recalculated if Matchdays 3–8 and cutoff / exclusion might have changed
- [ ] No `db push`, no migration, no deleted rows

---

## Functions this runbook uses

| Name | When |
| --- | --- |
| `set_match_result(match_id, home, away)` | Enter or correct a finished result. Rescores, Cup, badges. Admin page. |
| `recompute_players_cup()` | Freeze exclusions + rebuild Cup without changing a match result. Admin Cup panel. |
| `admin_recompute_badges()` | Rebuild all badge awards from current data. SQL Editor. Needed after SQL F. |
| `get_leaderboard()` | Read-only ranking. App standings page. |

Do not call internal helpers (`players_cup_freeze_exclusions`, `players_cup_apply`, `recompute_all_badges`) from day-to-day ops unless you are following a recovery note. The three functions above already wrap them.

---

## Open operational risks

These are current-system limitations. Do **not** patch production logic from this document.

| Issue | Severity | Recommended future fix |
| --- | --- | --- |
| No Admin UI to change kickoff, postpone, or cancel. Ops is SQL-only. | Medium | Small admin fixture form that updates `kickoff_at` / `status` with the same checks as this runbook. |
| Moving kickoff **later** on a still-`scheduled` match re-opens prediction and Golden Match edits after a lock had already passed. | Medium | Product rule: once a kickoff has passed, require `postponed` (not a later `scheduled` time) until the replay, **or** an explicit “reopen predictions” flag. |
| Restoring `postponed` → `scheduled` with a future kickoff unlocks Golden Match changes. | Medium | Same as above: keep postponed until result entry if UEFA did not grant a new pick window. |
| Re-opening a finished match without clearing `predictions.points` leaves points on the leaderboard. | High | An admin RPC that un-finishes a match, nulls that match’s points, and recomputes badges + Cup in one transaction. Until then, use SQL F exactly. |
| `badge_matchday_is_complete` requires **every** match `finished`. A **cancelled** (or stuck postponed) match **blocks matchday badges** for that round forever. | High | Define whether cancelled matches are excluded from matchday completeness, then implement that in badge logic — do not fake a 0–0 finish. |
| Players Cup cutoff is live `min(kickoff_at)` of the next matchday until freeze. Changing that first kickoff moves the cutoff. | High | Store cutoff at matchday create time, **or** freeze exclusions as soon as the next matchday’s first kickoff is reached (scheduled job). |
| Cup Final (MD8) has no cutoff. A postponed Final fixture can block the Final indefinitely. | Medium | Product decision: wait (current rules) vs. a Final-only exclusion policy. |
| Long-term predictions stay editable while any MD3 match is unfinished (including postponed). | Low | Acceptable if MD3 postponements are rare; otherwise lock LT on original MD3 end, not on “all finished”. |
| `matchdays.status` is unused; `starts_at` / `ends_at` can go stale without breaking locks. | Low | Ops discipline (this runbook) or a trigger that refreshes the window when kickoffs change. |
| `live` status is unused. Setting it locks predictions but Admin still looks like it can save a result. | Low | Either start using `live` in Admin, or hide it from operators. |
| Admin Data API can still **delete** match rows (RLS allows admin delete). | High | Never delete. Future: revoke delete on `matches` from `authenticated`. |

---

## Related app labels (Admin)

| Status | Greek label in Admin |
| --- | --- |
| scheduled | Προγραμματισμένος |
| live | Σε εξέλιξη |
| finished | Ολοκληρωμένος |
| postponed | Αναβλήθηκε |
| cancelled | Ακυρώθηκε |
