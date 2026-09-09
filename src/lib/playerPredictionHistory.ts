import { supabase } from './supabase'
import { compareMatchdays } from './stages'

export type PlayerPredictionHistoryRow = {
  match_id: number
  matchday_id: number
  matchday_stage: string
  matchday_number: number | null
  matchday_name: string
  kickoff_at: string
  home_team_name: string
  home_team_short_name: string | null
  away_team_name: string
  away_team_short_name: string | null
  home_score: number
  away_score: number
  predicted_home_score: number
  predicted_away_score: number
  points: number
  is_golden_match: boolean
}

export type PredictionResultKind = 'exact' | 'correct' | 'wrong'

export type PlayerPredictionHistoryGroup = {
  matchdayId: number
  stage: string
  matchdayNumber: number | null
  name: string
  matches: PlayerPredictionHistoryRow[]
}

/**
 * Mirrors public.prediction_is_exact / prediction_is_correct.
 * Uses the stored points value. Does not recompute scoring.
 */
export const classifyStoredPredictionPoints = (
  points: number,
): PredictionResultKind => {
  if (points === 5 || points === 10) {
    return 'exact'
  }

  if (points === 2 || points === 4) {
    return 'correct'
  }

  return 'wrong'
}

const compareHistoryMatchdays = (
  left: PlayerPredictionHistoryGroup,
  right: PlayerPredictionHistoryGroup,
) =>
  compareMatchdays(
    {
      id: right.matchdayId,
      stage: right.stage,
      matchday_number: right.matchdayNumber,
    },
    {
      id: left.matchdayId,
      stage: left.stage,
      matchday_number: left.matchdayNumber,
    },
  )

const compareHistoryMatches = (
  left: PlayerPredictionHistoryRow,
  right: PlayerPredictionHistoryRow,
) => {
  const kickoffDiff =
    new Date(left.kickoff_at).getTime() - new Date(right.kickoff_at).getTime()

  if (kickoffDiff !== 0) {
    return kickoffDiff
  }

  return left.match_id - right.match_id
}

export const groupPlayerPredictionHistory = (
  rows: PlayerPredictionHistoryRow[],
): PlayerPredictionHistoryGroup[] => {
  const groups = new Map<number, PlayerPredictionHistoryGroup>()

  rows.forEach((row) => {
    const current = groups.get(row.matchday_id)

    if (current) {
      current.matches.push(row)
      return
    }

    groups.set(row.matchday_id, {
      matchdayId: row.matchday_id,
      stage: row.matchday_stage,
      matchdayNumber: row.matchday_number,
      name: row.matchday_name,
      matches: [row],
    })
  })

  return Array.from(groups.values())
    .map((group) => ({
      ...group,
      matches: [...group.matches].sort(compareHistoryMatches),
    }))
    .sort(compareHistoryMatchdays)
}

export const fetchPlayerPredictionHistory = async (userId: string) => {
  const { data, error } = await supabase.rpc(
    'get_player_prediction_history',
    { p_user_id: userId },
  )

  if (error) {
    throw error
  }

  return groupPlayerPredictionHistory(
    (data ?? []) as PlayerPredictionHistoryRow[],
  )
}
