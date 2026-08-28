import { formatMatchdayLabel } from './stages'
import { supabase } from './supabase'

export type BadgeCode =
  | 'season_champion'
  | 'season_runner_up'
  | 'season_top_5'
  | 'league_phase_champion'
  | 'league_phase_runner_up'
  | 'players_cup_champion'
  | 'players_cup_finalist'
  | 'players_cup_semifinalist'
  | 'exact_machine'
  | 'sharp_shooter'
  | 'on_fire'
  | 'top_of_the_matchday'
  | 'second_of_the_matchday'
  | 'third_of_the_matchday'
  | 'final_boss'
  | 'perfect_matchday'
  | 'leader'

export type BadgeDefinition = {
  code: string
  title: string
  description: string
  image_path: string
  repeatable: boolean
  category: string
  sort_order: number
}

export type BadgeAwardContext = Record<string, unknown>

export type BadgeAwardRecord = {
  id: number
  badge_code: string
  award_scope: string
  season_label: string
  matchday_id: number | null
  cup_id: number | null
  context: BadgeAwardContext
  earned_at: string
  matchday_label: string | null
}

export type GroupedBadge = {
  code: string
  definition: BadgeDefinition
  count: number
  awards: BadgeAwardRecord[]
}

type BadgeAwardRow = {
  id: number
  badge_code: string
  award_scope: string
  season_label: string
  matchday_id: number | null
  cup_id: number | null
  context: unknown
  earned_at: string
}

type MatchdayRow = {
  id: number
  stage: string
  matchday_number: number | null
}

let definitionsCache: BadgeDefinition[] | null = null
let definitionsInFlight: Promise<BadgeDefinition[]> | null = null

const asRecord = (value: unknown): BadgeAwardContext => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {}
  }

  return value as BadgeAwardContext
}

const readNumber = (
  context: BadgeAwardContext,
  ...keys: string[]
): number | null => {
  for (const key of keys) {
    const value = context[key]

    if (typeof value === 'number' && Number.isFinite(value)) {
      return value
    }
  }

  return null
}

export function optimizedBadgeImagePath(imagePath: string) {
  const filename = imagePath.split('/').pop() ?? ''
  const slug = filename.replace(/\.png$/i, '')

  if (!slug) return imagePath

  return `/badges/optimized/${slug}.webp`
}

export function formatAwardDate(iso: string) {
  const date = new Date(iso)

  if (Number.isNaN(date.getTime())) {
    return ''
  }

  return new Intl.DateTimeFormat('el-GR', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(date)
}

export function formatUnlockedCount(count: number) {
  if (count === 1) {
    return 'Ξεκλειδώθηκε 1 φορά'
  }

  return `Ξεκλειδώθηκε ${count} φορές`
}

export function formatAwardContext(
  badgeCode: string,
  context: BadgeAwardContext | null,
): string | null {
  if (!context) return null

  const rank = readNumber(context, 'rank', 'rank_position', 'final_rank')
  const points = readNumber(context, 'points', 'total_points', 'matchday_points')
  const exactCount = readNumber(context, 'exact_count', 'exact_scores')
  const correctCount = readNumber(context, 'correct_count', 'correct_results')
  const matchCount = readNumber(context, 'match_count', 'total_matches')

  switch (badgeCode) {
    case 'top_of_the_matchday':
    case 'second_of_the_matchday':
    case 'third_of_the_matchday': {
      const parts: string[] = []

      if (rank !== null) parts.push(`${rank}η θέση`)
      if (points !== null) parts.push(`${points} βαθμοί`)

      return parts.length > 0 ? parts.join(' · ') : null
    }

    case 'sharp_shooter':
      return exactCount !== null ? `${exactCount} ακριβή σκορ` : null

    case 'on_fire':
      return points !== null ? `${points} βαθμοί` : null

    case 'perfect_matchday': {
      if (matchCount !== null && exactCount !== null && correctCount !== null) {
        return `${exactCount + correctCount}/${matchCount} σωστά αποτελέσματα`
      }

      if (matchCount !== null && correctCount !== null) {
        return `${correctCount}/${matchCount} σωστά αποτελέσματα`
      }

      return null
    }

    case 'exact_machine':
      return exactCount !== null ? `${exactCount} ακριβή σκορ` : null

    case 'leader':
      return '1η θέση στη γενική κατάταξη.'

    case 'season_champion':
    case 'season_runner_up':
    case 'season_top_5':
    case 'league_phase_champion':
    case 'league_phase_runner_up': {
      const parts: string[] = []

      if (rank !== null) parts.push(`${rank}η θέση`)
      if (points !== null) parts.push(`${points} βαθμοί`)

      return parts.length > 0 ? parts.join(' · ') : null
    }

    case 'players_cup_champion':
    case 'players_cup_finalist':
    case 'players_cup_semifinalist':
      return points !== null ? `+${points} βαθμοί` : null

    default:
      return null
  }
}

export async function fetchBadgeDefinitions() {
  if (definitionsCache) {
    return definitionsCache
  }

  if (!definitionsInFlight) {
    definitionsInFlight = (async () => {
      const { data, error } = await supabase
        .from('badge_definitions')
        .select(
          'code, title, description, image_path, repeatable, category, sort_order',
        )
        .order('sort_order', { ascending: true })

      if (error) {
        definitionsInFlight = null
        throw error
      }

      definitionsCache = (data ?? []) as BadgeDefinition[]
      return definitionsCache
    })()
  }

  return definitionsInFlight
}

export async function fetchEarnedBadges(userId: string): Promise<GroupedBadge[]> {
  const [definitions, awardsResult] = await Promise.all([
    fetchBadgeDefinitions(),
    supabase
      .from('badge_awards')
      .select(
        'id, badge_code, award_scope, season_label, matchday_id, cup_id, context, earned_at',
      )
      .eq('user_id', userId),
  ])

  if (awardsResult.error) {
    throw awardsResult.error
  }

  const awards = (awardsResult.data ?? []) as BadgeAwardRow[]
  const matchdayIds = [
    ...new Set(
      awards
        .map((award) => award.matchday_id)
        .filter((id): id is number => id != null),
    ),
  ]

  const matchdayLabels = new Map<number, string>()

  if (matchdayIds.length > 0) {
    const { data: matchdays, error: matchdayError } = await supabase
      .from('matchdays')
      .select('id, stage, matchday_number')
      .in('id', matchdayIds)

    if (!matchdayError) {
      for (const matchday of (matchdays ?? []) as MatchdayRow[]) {
        matchdayLabels.set(
          matchday.id,
          formatMatchdayLabel(matchday.stage, matchday.matchday_number),
        )
      }
    }
  }

  const definitionByCode = new Map(
    definitions.map((definition) => [definition.code, definition]),
  )
  const grouped = new Map<string, BadgeAwardRecord[]>()

  for (const award of awards) {
    const record: BadgeAwardRecord = {
      id: award.id,
      badge_code: award.badge_code,
      award_scope: award.award_scope,
      season_label: award.season_label,
      matchday_id: award.matchday_id,
      cup_id: award.cup_id,
      context: asRecord(award.context),
      earned_at: award.earned_at,
      matchday_label:
        award.matchday_id != null
          ? (matchdayLabels.get(award.matchday_id) ?? null)
          : null,
    }

    const current = grouped.get(award.badge_code) ?? []
    current.push(record)
    grouped.set(award.badge_code, current)
  }

  const badges: GroupedBadge[] = []

  for (const [code, records] of grouped) {
    const definition = definitionByCode.get(code)

    if (!definition) continue

    records.sort((left, right) => {
      const byDate = right.earned_at.localeCompare(left.earned_at)

      if (byDate !== 0) return byDate

      return right.id - left.id
    })

    badges.push({
      code,
      definition,
      count: records.length,
      awards: records,
    })
  }

  badges.sort(
    (left, right) => left.definition.sort_order - right.definition.sort_order,
  )

  return badges
}
