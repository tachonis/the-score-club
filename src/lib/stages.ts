/**
 * Canonical frontend convention for Champions League competition stages.
 *
 * Display labels and ordering are derived from `stage` + `matchday_number`.
 * `matchdays.name` is optional operational metadata only — never the source
 * of truth for sorting or player/admin labels.
 *
 * Future fixture entry (manual, after UEFA publishes a round — do not
 * pre-create empty knockout rounds):
 * 1. Two-legged rounds get two matchday rows.
 * 2. Use the existing stage values below; never invent aliases.
 * 3. First leg = matchday_number 1, second leg = matchday_number 2.
 * 4. Each real match is its own row with its own kickoff.
 * 5. The Final is one matchday: stage `final`, matchday_number 1.
 * 6. Do not insert later knockout rounds until UEFA confirms the pairings.
 * 7. There is no automatic bracket, qualifier, aggregate, extra-time or
 *    penalty entity — next-round fixtures are entered by hand.
 */

import { t } from '../i18n'

export const COMPETITION_STAGE_SEQUENCE = [
  'league_phase',
  'playoff',
  'round_of_16',
  'quarter_final',
  'semi_final',
  'final',
] as const

export type CompetitionStage = (typeof COMPETITION_STAGE_SEQUENCE)[number]

export const STAGE_ORDER = {
  league_phase: 1,
  playoff: 2,
  round_of_16: 3,
  quarter_final: 4,
  semi_final: 5,
  final: 6,
} as const satisfies Record<CompetitionStage, number>

export const STAGE_LABELS = {
  league_phase: t('stage.leaguePhase'),
  playoff: t('stage.playoff'),
  round_of_16: t('stage.roundOf16'),
  quarter_final: t('stage.quarterFinal'),
  semi_final: t('stage.semiFinal'),
  final: t('stage.final'),
} as const satisfies Record<CompetitionStage, string>

export const KNOCKOUT_LEG_LABELS = {
  1: t('matchday.firstLeg'),
  2: t('matchday.secondLeg'),
} as const

export type MatchdaySortKey = {
  id?: number | null
  stage: string
  matchday_number: number | null
}

export const isCompetitionStage = (
  stage: string,
): stage is CompetitionStage => {
  return (COMPETITION_STAGE_SEQUENCE as readonly string[]).includes(stage)
}

export const isLeaguePhaseStage = (stage: string) => {
  return stage === 'league_phase'
}

export const isFinalStage = (stage: string) => {
  return stage === 'final'
}

export const isGoldenMatchStage = (stage: string) => {
  return stage === 'league_phase'
}

export const isKnockoutPredictionStage = (stage: string) => {
  return isCompetitionStage(stage) && stage !== 'league_phase'
}

export const isGoldenMatchAvailable = (
  stage: string,
  matchdayNumber: number | null,
) => {
  return isGoldenMatchStage(stage) && (matchdayNumber ?? 0) >= 2
}

export const getStageOrder = (stage: string) => {
  if (isCompetitionStage(stage)) {
    return STAGE_ORDER[stage]
  }

  return Number.MAX_SAFE_INTEGER
}

export const getStageLabel = (stage: string) => {
  if (isCompetitionStage(stage)) {
    return STAGE_LABELS[stage]
  }

  return stage
}

export const getMatchdayHeadingEyebrow = (stage: string) => {
  if (isFinalStage(stage)) {
    return t('stage.knockoutStage')
  }

  return getStageLabel(stage)
}

export const formatLeaguePhaseOrdinal = (matchdayNumber: number) => {
  return t('matchday.ordinal', { n: matchdayNumber })
}

export const formatLeaguePhaseRound = (matchdayNumber: number) => {
  return t('matchday.round', { n: matchdayNumber })
}

export const formatKnockoutLeg = (matchdayNumber: number) => {
  if (matchdayNumber === 1 || matchdayNumber === 2) {
    return KNOCKOUT_LEG_LABELS[matchdayNumber]
  }

  return null
}

export function formatMatchdayLabel(
  stage: string,
  matchdayNumber: number | null,
  fallbackName?: string | null,
): string {
  const fallback = fallbackName?.trim() || null

  if (!isCompetitionStage(stage)) {
    return fallback ?? stage
  }

  if (stage === 'league_phase') {
    if (matchdayNumber == null) {
      return fallback ?? STAGE_LABELS.league_phase
    }

    return t('matchday.full', {
      stage: STAGE_LABELS.league_phase,
      round: formatLeaguePhaseRound(matchdayNumber),
    })
  }

  if (stage === 'final') {
    return STAGE_LABELS.final
  }

  if (matchdayNumber != null) {
    const leg = formatKnockoutLeg(matchdayNumber)

    if (leg) {
      return t('matchday.full', {
        stage: STAGE_LABELS[stage],
        round: leg,
      })
    }
  }

  return fallback ?? STAGE_LABELS[stage]
}

export const getMatchdayRoundLabel = (
  stage: string,
  matchdayNumber: number | null,
  fallbackName?: string | null,
) => {
  if (isLeaguePhaseStage(stage) && matchdayNumber != null) {
    return formatLeaguePhaseRound(matchdayNumber)
  }

  if (isFinalStage(stage)) {
    return STAGE_LABELS.final
  }

  if (matchdayNumber != null) {
    const leg = formatKnockoutLeg(matchdayNumber)

    if (leg) {
      return leg
    }
  }

  return fallbackName?.trim() || getStageLabel(stage)
}

export const formatMatchdayTabLabel = (
  stage: string,
  matchdayNumber: number | null,
  fallbackName?: string | null,
) => {
  if (isLeaguePhaseStage(stage) && matchdayNumber != null) {
    return t('matchday.tabCompact', { n: matchdayNumber })
  }

  if (isFinalStage(stage)) {
    return STAGE_LABELS.final
  }

  if (matchdayNumber === 1 || matchdayNumber === 2) {
    if (stage === 'playoff') {
      return t(matchdayNumber === 1 ? 'matchday.tabPlayoff1' : 'matchday.tabPlayoff2')
    }

    if (stage === 'round_of_16') {
      return t(
        matchdayNumber === 1
          ? 'matchday.tabRoundOf16_1'
          : 'matchday.tabRoundOf16_2',
      )
    }

    if (stage === 'quarter_final') {
      return t(matchdayNumber === 1 ? 'matchday.tabQuarter1' : 'matchday.tabQuarter2')
    }

    if (stage === 'semi_final') {
      return t(matchdayNumber === 1 ? 'matchday.tabSemi1' : 'matchday.tabSemi2')
    }
  }

  return formatMatchdayLabel(stage, matchdayNumber, fallbackName)
}

export const compareMatchdays = (
  left: MatchdaySortKey,
  right: MatchdaySortKey,
) => {
  const stageDiff = getStageOrder(left.stage) - getStageOrder(right.stage)

  if (stageDiff !== 0) {
    return stageDiff
  }

  const numberDiff =
    (left.matchday_number ?? 0) - (right.matchday_number ?? 0)

  if (numberDiff !== 0) {
    return numberDiff
  }

  return (left.id ?? 0) - (right.id ?? 0)
}

export const isMatchdayComplete = (
  matches: { status: string }[] | null | undefined,
) => {
  if (!matches || matches.length === 0) {
    return false
  }

  return matches.every((match) => match.status === 'finished')
}

export const isLeaguePhaseMatchdayOneComplete = (
  matchdays: Array<{
    stage: string
    matchday_number: number | null
    matches?: { status: string }[] | null
  }>,
) => {
  const matchdayOne = matchdays.find(
    (matchday) =>
      isLeaguePhaseStage(matchday.stage) && matchday.matchday_number === 1,
  )

  return Boolean(matchdayOne && isMatchdayComplete(matchdayOne.matches))
}

export const selectDefaultLeaguePhaseMatchdayId = (
  matchdays: Array<
    MatchdaySortKey & { matches?: { status: string }[] | null }
  >,
) => {
  const leaguePhaseMatchdays = matchdays
    .filter(
      (matchday) =>
        isLeaguePhaseStage(matchday.stage) && matchday.id != null,
    )
    .sort(compareMatchdays)

  if (leaguePhaseMatchdays.length === 0) {
    return null
  }

  const populated = leaguePhaseMatchdays.filter(
    (matchday) => (matchday.matches ?? []).length > 0,
  )
  const candidates =
    populated.length > 0 ? populated : leaguePhaseMatchdays

  const inProgress = candidates.find(
    (matchday) => !isMatchdayComplete(matchday.matches),
  )

  if (inProgress) {
    return inProgress.id ?? null
  }

  return candidates[candidates.length - 1]?.id ?? null
}

type StageOrderAligned =
  (typeof STAGE_ORDER)['league_phase'] extends 1
    ? (typeof STAGE_ORDER)['playoff'] extends 2
      ? (typeof STAGE_ORDER)['round_of_16'] extends 3
        ? (typeof STAGE_ORDER)['quarter_final'] extends 4
          ? (typeof STAGE_ORDER)['semi_final'] extends 5
            ? (typeof STAGE_ORDER)['final'] extends 6
              ? true
              : never
            : never
          : never
        : never
      : never
    : never

const _stageOrderOk: StageOrderAligned = true
void _stageOrderOk
