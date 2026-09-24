import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { isPredictionMatchLocked } from '../src/lib/predictionLock.ts'
import { generateRandomFootballScore } from '../src/lib/randomScore.ts'
import {
  applyRandomiseMatchdayDraft,
  isEligibleForMatchdayRandomise,
  isFullyEmptyPrediction,
  predictionDraftDiffersFromSaved,
} from '../src/lib/randomiseMatchday.ts'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relativePath) =>
  readFileSync(path.join(root, relativePath), 'utf8')

const sequentialRandom = (values) => {
  let index = 0

  return () => {
    const value = values[index % values.length]
    index += 1
    return value
  }
}

const match = (id, status = 'scheduled', kickoffAt = '2099-01-01T18:00:00.000Z') => ({
  id,
  status,
  kickoff_at: kickoffAt,
})

const lockAt = (at, locallyLocked = new Set()) => (item) =>
  isPredictionMatchLocked(item, at, locallyLocked)

const draft = (home, away) => ({ home, away })

const countDirty = (predictions, saved, matches) =>
  matches.filter((item) =>
    predictionDraftDiffersFromSaved(predictions[item.id], saved[item.id]),
  ).length

test('fills only fully empty predictions', () => {
  const matches = [match(1), match(2), match(3)]
  const predictions = {
    1: draft('', ''),
    2: draft('1', '0'),
  }
  const random = sequentialRandom([0.01, 0.99])
  const result = applyRandomiseMatchdayDraft(
    predictions,
    matches,
    lockAt(0),
    random,
  )

  assert.equal(result.filledCount, 2)
  assert.deepEqual(result.predictions[1], draft('0', '5'))
  assert.deepEqual(result.predictions[3], draft('0', '5'))
  assert.deepEqual(result.predictions[2], draft('1', '0'))
  assert.equal(predictions[3], undefined)
})

test('preserves completed draft predictions', () => {
  const matches = [match(1), match(2)]
  const predictions = {
    1: draft('2', '2'),
    2: draft('', ''),
  }
  const result = applyRandomiseMatchdayDraft(
    predictions,
    matches,
    lockAt(0),
    () => 0,
  )

  assert.deepEqual(result.predictions[1], draft('2', '2'))
  assert.equal(result.predictions[1], predictions[1])
})

test('preserves saved predictions', () => {
  const matches = [match(1)]
  const saved = { 1: draft('1', '1') }
  const predictions = { 1: draft('', '') }
  const result = applyRandomiseMatchdayDraft(
    predictions,
    matches,
    lockAt(0),
    () => 0,
  )

  assert.deepEqual(saved[1], draft('1', '1'))
  assert.notEqual(result.predictions, saved)
  assert.deepEqual(predictions[1], draft('', ''))
})

test('preserves partial predictions', () => {
  assert.equal(isFullyEmptyPrediction({ home: '2', away: '' }), false)
  assert.equal(isFullyEmptyPrediction({ home: '', away: '1' }), false)
  assert.equal(isFullyEmptyPrediction(undefined), true)
  assert.equal(isFullyEmptyPrediction({ home: '', away: '' }), true)

  const matches = [match(1), match(2)]
  const predictions = {
    1: draft('2', ''),
    2: draft('', ''),
  }
  const result = applyRandomiseMatchdayDraft(
    predictions,
    matches,
    lockAt(0),
    () => 0,
  )

  assert.equal(result.filledCount, 1)
  assert.deepEqual(result.predictions[1], draft('2', ''))
  assert.equal(result.predictions[1], predictions[1])
})

test('skips locked matches', () => {
  const now = Date.parse('2026-09-24T12:00:00.000Z')
  const locked = match(1)
  const open = match(2)
  const locallyLocked = new Set([1])
  const isLocked = lockAt(now, locallyLocked)
  const predictions = {
    1: draft('', ''),
    2: draft('', ''),
  }

  assert.equal(isLocked(locked), true)
  assert.equal(
    isEligibleForMatchdayRandomise(locked, predictions, isLocked),
    false,
  )

  const result = applyRandomiseMatchdayDraft(
    predictions,
    [locked, open],
    isLocked,
    () => 0,
  )

  assert.equal(result.filledCount, 1)
  assert.deepEqual(result.predictions[1], draft('', ''))
  assert.deepEqual(result.predictions[2], draft('0', '0'))
})

test('skips started and non-scheduled matches', () => {
  const now = Date.parse('2026-09-24T12:00:00.000Z')
  const started = match(1, 'scheduled', '2026-09-24T11:00:00.000Z')
  const live = match(2, 'live', '2026-09-25T18:00:00.000Z')
  const finished = match(3, 'finished', '2026-09-25T18:00:00.000Z')
  const open = match(4, 'scheduled', '2026-09-25T18:00:00.000Z')
  const isLocked = lockAt(now)
  const predictions = {}

  const result = applyRandomiseMatchdayDraft(
    predictions,
    [started, live, finished, open],
    isLocked,
    () => 0.01,
  )

  assert.equal(isPredictionMatchLocked(started, now, new Set()), true)
  assert.equal(isPredictionMatchLocked(live, now, new Set()), true)
  assert.equal(isPredictionMatchLocked(finished, now, new Set()), true)
  assert.equal(isPredictionMatchLocked(open, now, new Set()), false)
  assert.equal(result.filledCount, 1)
  assert.equal(result.predictions[1], undefined)
  assert.equal(result.predictions[2], undefined)
  assert.equal(result.predictions[3], undefined)
  assert.deepEqual(result.predictions[4].home, '0')
  assert.ok(result.predictions[4].away !== '')
})

test('uses existing random score helper', () => {
  const calls = []
  const random = () => {
    calls.push('random')
    return 0.4
  }
  const expected = generateRandomFootballScore(sequentialRandom([0.4, 0.4]))
  const result = applyRandomiseMatchdayDraft(
    { 8: draft('', '') },
    [match(8)],
    () => false,
    random,
  )

  assert.equal(calls.length, 2)
  assert.deepEqual(result.predictions[8], {
    home: String(expected.home),
    away: String(expected.away),
  })
})

test('produces a complete home and away score pair', () => {
  const result = applyRandomiseMatchdayDraft(
    {},
    [match(1)],
    () => false,
    sequentialRandom([0.2, 0.8]),
  )
  const score = result.predictions[1]

  assert.match(score.home, /^\d+$/)
  assert.match(score.away, /^\d+$/)
  assert.notEqual(score.home, '')
  assert.notEqual(score.away, '')
})

test('second randomise with no empty matches does nothing', () => {
  const matches = [match(1), match(2)]
  const first = applyRandomiseMatchdayDraft(
    { 1: draft('', ''), 2: draft('', '') },
    matches,
    () => false,
    () => 0.2,
  )
  const second = applyRandomiseMatchdayDraft(
    first.predictions,
    matches,
    () => false,
    () => 0.99,
  )

  assert.equal(first.filledCount, 2)
  assert.equal(second.filledCount, 0)
  assert.equal(second.predictions, first.predictions)
})

test('dirty count stays compatible and saved rows stay unchanged', () => {
  const matches = [match(1), match(2), match(3)]
  const saved = {
    1: draft('1', '0'),
    2: draft('', ''),
  }
  const predictions = {
    1: draft('1', '0'),
    2: draft('', ''),
    3: draft('2', ''),
  }
  const result = applyRandomiseMatchdayDraft(
    predictions,
    matches,
    () => false,
    () => 0,
  )

  assert.equal(countDirty(predictions, saved, matches), 1)
  assert.equal(countDirty(result.predictions, saved, matches), 2)
  assert.deepEqual(saved[1], draft('1', '0'))
  assert.deepEqual(result.predictions[1], draft('1', '0'))
  assert.deepEqual(result.predictions[3], draft('2', ''))
  assert.deepEqual(result.predictions[2], draft('0', '0'))
})

test('manual edit after randomise remains possible', () => {
  const matches = [match(1)]
  const saved = {}
  const result = applyRandomiseMatchdayDraft(
    {},
    matches,
    () => false,
    () => 0,
  )
  const edited = {
    ...result.predictions,
    1: {
      home: '4',
      away: result.predictions[1].away,
    },
  }

  assert.deepEqual(result.predictions[1], draft('0', '0'))
  assert.deepEqual(edited[1], draft('4', '0'))
  assert.equal(countDirty(edited, saved, matches), 1)
  assert.equal(predictionDraftDiffersFromSaved(edited[1], saved[1]), true)
})

test('clearing a randomised score makes the row eligible again', () => {
  const item = match(1)
  const filled = applyRandomiseMatchdayDraft({}, [item], () => false, () => 0)
  const cleared = {
    ...filled.predictions,
    1: draft('', ''),
  }

  assert.equal(
    isEligibleForMatchdayRandomise(item, filled.predictions, () => false),
    false,
  )
  assert.equal(
    isEligibleForMatchdayRandomise(item, cleared, () => false),
    true,
  )
})

test('PredictionsPage wires matchday randomise into draft state only', () => {
  const source = read('src/pages/PredictionsPage.tsx')

  assert.match(source, /applyRandomiseMatchdayDraft/)
  assert.match(source, /isEligibleForMatchdayRandomise/)
  assert.match(source, /isPredictionMatchLocked/)
  assert.match(source, /className="randomise-matchday-button"/)
  assert.match(source, /className="randomise-matchday-dialog"/)
  assert.match(source, /predictions\.randomiseMatchday/)
  assert.match(source, /predictions\.randomiseMatchdayConfirm/)
  assert.match(source, /predictions\.randomiseMatchdayNote/)
  assert.match(source, /predictions\.randomiseMatchdayAction/)
  assert.match(source, /common\.cancel/)
  assert.doesNotMatch(source, /window\.confirm/)

  const handlerStart = source.indexOf('const handleConfirmRandomiseMatchday =')
  const handlerEnd = source.indexOf(
    'const handleGoldenMatchSelection',
    handlerStart,
  )
  const handlerSlice = source.slice(handlerStart, handlerEnd)

  assert.match(handlerSlice, /if \(saving\)/)
  assert.match(handlerSlice, /setPredictions\(\(currentPredictions\) =>/)
  assert.match(handlerSlice, /isMatchLocked/)
  assert.doesNotMatch(handlerSlice, /\.upsert\(/)
  assert.doesNotMatch(handlerSlice, /savedPredictions/)
  assert.doesNotMatch(handlerSlice, /supabase/)
  assert.doesNotMatch(handlerSlice, /setSavedPredictions/)
})

test('existing per-match Random Score handler is unchanged', () => {
  const source = read('src/pages/PredictionsPage.tsx')
  const handlerStart = source.indexOf('const handleRandomScore =')
  const handlerEnd = source.indexOf('const closeRandomiseConfirm', handlerStart)
  const handlerSlice = source.slice(handlerStart, handlerEnd)

  assert.match(handlerSlice, /generateRandomFootballScore\(\)/)
  assert.match(handlerSlice, /isMatchLocked\(match\)/)
  assert.match(handlerSlice, /setPredictions/)
  assert.match(handlerSlice, /String\(score\.home\)/)
  assert.match(handlerSlice, /String\(score\.away\)/)
  assert.doesNotMatch(handlerSlice, /applyRandomiseMatchdayDraft/)
  assert.doesNotMatch(handlerSlice, /\.upsert\(/)
})

test('save path still upserts dirty drafts and uses the same lock helper', () => {
  const source = read('src/pages/PredictionsPage.tsx')
  const saveStart = source.indexOf('const handleSavePredictions =')
  const saveSlice = source.slice(saveStart, saveStart + 4500)

  assert.match(saveSlice, /\.from\('predictions'\)\.upsert/)
  assert.match(saveSlice, /onConflict: 'user_id,match_id'/)
  assert.match(saveSlice, /dirtyCompleteMatches/)
  assert.match(saveSlice, /isMatchLockedAt/)
  assert.match(source, /predictionDraftDiffersFromSaved/)
  assert.match(source, /isPredictionMatchLocked\(match, at, locallyLockedMatchIds\)/)
})

test('i18n includes Randomise Matchday copy in both locales', () => {
  const el = read('src/i18n/el.ts')
  const en = read('src/i18n/en.ts')

  assert.match(el, /randomiseMatchday: 'Τυχαία συμπλήρωση'/)
  assert.match(
    el,
    /Να συμπληρωθούν με τυχαία σκορ όλες οι κενές προβλέψεις της αγωνιστικής;/,
  )
  assert.match(el, /Οι ήδη συμπληρωμένες προβλέψεις δεν θα αλλάξουν\./)
  assert.match(el, /randomiseMatchdayAction: 'Τυχαία συμπλήρωση'/)
  assert.match(en, /randomiseMatchday: 'Randomise Matchday'/)
  assert.match(
    en,
    /Fill all empty predictions in this matchday with random scores\?/,
  )
  assert.match(en, /Existing predictions will not be changed\./)
  assert.match(en, /randomiseMatchdayAction: 'Randomise'/)
})
