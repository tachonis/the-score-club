import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import {
  FOOTBALL_GOAL_WEIGHTS,
  RANDOM_FOOTBALL_MAX_GOALS,
  generateRandomFootballScore,
  pickWeighted,
} from '../src/lib/randomScore.ts'

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

test('football goal weights cover 0..max with positive weights', () => {
  assert.equal(RANDOM_FOOTBALL_MAX_GOALS, 5)
  assert.ok(FOOTBALL_GOAL_WEIGHTS.length > 0)

  const goals = FOOTBALL_GOAL_WEIGHTS.map((entry) => entry.goals)

  assert.deepEqual(goals, [0, 1, 2, 3, 4, 5])

  for (const entry of FOOTBALL_GOAL_WEIGHTS) {
    assert.equal(Number.isInteger(entry.goals), true)
    assert.equal(Number.isInteger(entry.weight), true)
    assert.ok(entry.goals >= 0)
    assert.ok(entry.goals <= RANDOM_FOOTBALL_MAX_GOALS)
    assert.ok(entry.weight > 0)
  }
})

test('pickWeighted returns items by cumulative weight', () => {
  const items = [
    { id: 'a', weight: 1 },
    { id: 'b', weight: 1 },
  ]

  assert.equal(pickWeighted(items, () => 0).id, 'a')
  assert.equal(pickWeighted(items, () => 0.49).id, 'a')
  assert.equal(pickWeighted(items, () => 0.5).id, 'b')
  assert.equal(pickWeighted(items, () => 0.999).id, 'b')
})

test('generateRandomFootballScore returns valid integers within bounds', () => {
  for (let i = 0; i < 200; i += 1) {
    const score = generateRandomFootballScore()

    assert.equal(Number.isInteger(score.home), true)
    assert.equal(Number.isInteger(score.away), true)
    assert.ok(score.home >= 0)
    assert.ok(score.away >= 0)
    assert.ok(score.home <= RANDOM_FOOTBALL_MAX_GOALS)
    assert.ok(score.away <= RANDOM_FOOTBALL_MAX_GOALS)
  }
})

test('generateRandomFootballScore never throws on repeated calls', () => {
  assert.doesNotThrow(() => {
    for (let i = 0; i < 500; i += 1) {
      generateRandomFootballScore()
    }
  })
})

test('generateRandomFootballScore is deterministic with a seeded random source', () => {
  const random = sequentialRandom([0.01, 0.99, 0.4, 0.6])
  const first = generateRandomFootballScore(random)
  const second = generateRandomFootballScore(random)

  assert.deepEqual(first, { home: 0, away: 5 })
  assert.ok(second.home >= 0)
  assert.ok(second.away >= 0)
  assert.ok(second.home <= RANDOM_FOOTBALL_MAX_GOALS)
  assert.ok(second.away <= RANDOM_FOOTBALL_MAX_GOALS)
})

test('repeated samples stay inside a reasonable football score pool', () => {
  const seen = new Set()

  for (let i = 0; i < 400; i += 1) {
    const score = generateRandomFootballScore()
    seen.add(`${score.home}-${score.away}`)
  }

  assert.ok(seen.size >= 8)

  for (const line of seen) {
    const [homeText, awayText] = line.split('-')
    const home = Number(homeText)
    const away = Number(awayText)

    assert.ok(home + away <= RANDOM_FOOTBALL_MAX_GOALS * 2)
    assert.ok(home <= RANDOM_FOOTBALL_MAX_GOALS)
    assert.ok(away <= RANDOM_FOOTBALL_MAX_GOALS)
  }

  // Common low-scoring lines should appear often enough in a large sample.
  const commonLines = ['0-0', '1-0', '0-1', '1-1', '2-1', '1-2', '2-0', '0-2']
  const hitCommon = commonLines.some((line) => seen.has(line))
  assert.equal(hitCommon, true)
})

test('PredictionsPage wires Random Score into draft state only', () => {
  const source = read('src/pages/PredictionsPage.tsx')

  assert.match(source, /from '\.\.\/lib\/randomScore'/)
  assert.match(source, /generateRandomFootballScore/)
  assert.match(source, /handleRandomScore/)
  assert.match(source, /className="random-score-button"/)
  assert.match(source, /predictions\.randomScore/)
  assert.match(source, /predictions\.randomScoreHelp/)

  // Draft mutation only — no auto-save / upsert inside the random handler.
  const handlerStart = source.indexOf('const handleRandomScore =')
  assert.ok(handlerStart >= 0)

  const handlerSlice = source.slice(
    handlerStart,
    source.indexOf('const handleGoldenMatchSelection', handlerStart),
  )

  assert.match(handlerSlice, /isMatchLocked\(match\)/)
  assert.match(handlerSlice, /setPredictions/)
  assert.match(handlerSlice, /String\(score\.home\)/)
  assert.match(handlerSlice, /String\(score\.away\)/)
  assert.doesNotMatch(handlerSlice, /\.upsert\(/)
  assert.doesNotMatch(handlerSlice, /savedPredictions/)
  assert.doesNotMatch(handlerSlice, /supabase/)
})

test('i18n includes Random Score labels in both locales', () => {
  const el = read('src/i18n/el.ts')
  const en = read('src/i18n/en.ts')

  assert.match(el, /randomScore: 'Τυχαίο σκορ'/)
  assert.match(el, /randomScoreHelp: 'Δημιουργία τυχαίου σκορ'/)
  assert.match(en, /randomScore: 'Random score'/)
  assert.match(en, /randomScoreHelp: 'Generate a random score'/)
})

test('Save predictions path still uses explicit upsert (unchanged contract)', () => {
  const source = read('src/pages/PredictionsPage.tsx')
  const saveStart = source.indexOf('const handleSavePredictions =')
  assert.ok(saveStart >= 0)

  const saveSlice = source.slice(saveStart, saveStart + 4500)

  assert.match(saveSlice, /\.from\('predictions'\)\.upsert/)
  assert.match(saveSlice, /onConflict: 'user_id,match_id'/)
  assert.match(saveSlice, /dirtyCompleteMatches/)
})
