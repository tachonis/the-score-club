export type MatchPlayerPrediction = {
  match_id: number
  user_id: string
  username: string
  predicted_home_score: number
  predicted_away_score: number
  points: number | null
  is_golden_match: boolean
}

export const hasMatchKickedOff = (kickoffAt: string, at: number) =>
  at >= new Date(kickoffAt).getTime()

export const groupMatchPlayerPredictions = (
  rows: MatchPlayerPrediction[],
) => {
  const grouped: Record<number, MatchPlayerPrediction[]> = {}

  rows.forEach((row) => {
    const current = grouped[row.match_id]

    if (current) {
      current.push(row)
    } else {
      grouped[row.match_id] = [row]
    }
  })

  return grouped
}
