import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import {
  favoriteIdFromSelection,
  selectionFromFavorite,
  teamsForPicker,
} from '../src/lib/favoriteTeamSelection.ts'
import {
  NEUTRAL_SHIELD,
  TEAM_SHIELD_PALETTES,
  isNeutralShield,
  paletteForTeamName,
} from '../src/lib/teamIdentity.ts'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relativePath) =>
  readFileSync(path.join(root, relativePath), 'utf8')

const seedNames = (sql, startMarker, endMarker) => {
  const start = sql.indexOf(startMarker)
  const end = sql.indexOf(endMarker, start)
  const block = sql.slice(start, end)
  return [...block.matchAll(/\('([^']+)'/g)].map((match) => match[1])
}

const englishSeed = read('supabase/english-bootstrap/0002_official_seed.sql')
const greekSeed = read(
  'supabase/migrations/20260829174500_official_2026_27_league_phase_import.sql',
)
const officialNames = seedNames(
  englishSeed,
  'insert into public.teams (name, short_name, country)',
  'insert into public.matchdays',
)
const greekNames = seedNames(
  greekSeed,
  'insert into official_2026_27_teams (name, short_name, country)',
  'create temporary table official_2026_27_fixtures',
)

test('shield colors follow canonical team names', () => {
  assert.deepEqual(officialNames.slice().sort(), greekNames.slice().sort())
  assert.equal(officialNames.length, 36)
  assert.deepEqual(
    Object.keys(TEAM_SHIELD_PALETTES).sort(),
    officialNames.slice().sort(),
  )

  const arsenal = paletteForTeamName('Arsenal')
  assert.equal(arsenal.primary, '#D71920')
  assert.equal(arsenal.secondary, '#FFFFFF')
  assert.equal(arsenal.lightField, false)

  const madrid = paletteForTeamName('Real Madrid')
  assert.equal(madrid.primary, '#FFFFFF')
  assert.equal(madrid.lightField, true)
  assert.equal(paletteForTeamName('RB Leipzig').lightField, true)
  assert.equal(paletteForTeamName('Stuttgart').lightField, true)
})

test('none and unknown teams use the neutral shield', () => {
  assert.deepEqual(paletteForTeamName(null), NEUTRAL_SHIELD)
  assert.deepEqual(paletteForTeamName(undefined), NEUTRAL_SHIELD)
  assert.equal(isNeutralShield(paletteForTeamName('Not A Club')), true)
  assert.equal(NEUTRAL_SHIELD.primary, '#183E45')
  assert.equal(NEUTRAL_SHIELD.secondary, '#D28B45')
})

test('white-primary shields request a dark outline', () => {
  const shield = read('src/components/PlayerShield.tsx')
  assert.match(shield, /lightField/)
  assert.match(shield, /#102C32/)
  assert.equal(paletteForTeamName('Real Madrid').lightField, true)
  assert.equal(paletteForTeamName('Arsenal').lightField, false)
})

test('PlayerShield does not render an official logo', () => {
  const shield = read('src/components/PlayerShield.tsx')
  assert.doesNotMatch(shield, /logo_url|<image|<img|<text/i)
  assert.match(shield, /<svg/)
})

test('team picker includes None and keeps every supplied team', () => {
  const dialog = read('src/components/FavoriteTeamDialog.tsx')
  assert.match(dialog, /NONE_TEAM_VALUE/)
  assert.match(dialog, /profile\.noTeam/)
  assert.match(dialog, /role="radiogroup"/)
  assert.match(dialog, /aria-labelledby/)

  const teams = [
    { id: 2, name: 'Villarreal' },
    { id: 1, name: 'Arsenal' },
  ]
  const options = teamsForPicker(teams, { id: 9, name: 'Retired FC' })

  assert.deepEqual(
    options.map((team) => team.name),
    ['Arsenal', 'Retired FC', 'Villarreal'],
  )
  assert.equal(options.length, teams.length + 1)
})

test('saving None produces null and an existing favorite reloads', () => {
  assert.equal(favoriteIdFromSelection('none'), null)
  assert.equal(favoriteIdFromSelection(''), null)
  assert.equal(favoriteIdFromSelection('15'), 15)
  assert.equal(selectionFromFavorite(null), 'none')
  assert.equal(selectionFromFavorite(15), '15')

  const profile = read('src/pages/PlayerProfilePage.tsx')
  assert.match(profile, /favorite_team_id: favoriteTeamId/)
  assert.match(profile, /PlayerShield/)
  assert.match(profile, /profile\.editProfile/)
  assert.match(profile, /profile\.supports/)
  assert.doesNotMatch(profile, /set role|set status|display_name/)
})

test('leaderboard contract includes favorite_team_id and a shield', () => {
  const migration = read(
    'supabase/migrations/20260924140000_profile_favorite_team.sql',
  )
  const standings = read('src/pages/StandingsPage.tsx')

  assert.match(migration, /favorite_team_id bigint/)
  assert.match(migration, /on delete set null/i)
  assert.match(
    migration,
    /grant update \(favorite_team_id\) on table public\.profiles to authenticated/,
  )
  assert.doesNotMatch(
    migration,
    /grant update on table public\.profiles to authenticated/i,
  )
  assert.match(standings, /favorite_team_id/)
  assert.match(standings, /PlayerShield/)
  assert.doesNotMatch(standings, /tsc-player-avatar|charAt\(0\)/)
})

test('Players Cup shield comes from the current profile, not the snapshot', () => {
  const cup = read('src/lib/cup.ts')
  const card = read('src/components/cup/CupTieCard.tsx')
  const participantsSelect = cup.slice(
    cup.indexOf(".from('cup_participants')"),
    cup.indexOf(".from('cup_rounds')"),
  )

  assert.match(participantsSelect, /username_snapshot/)
  assert.doesNotMatch(participantsSelect, /favorite_team/)
  assert.match(cup, /favorite_team_id/)
  assert.match(cup, /\.from\('profiles'\)/)
  assert.match(card, /PlayerShield/)
  assert.match(card, /favorite_team_name/)
})
