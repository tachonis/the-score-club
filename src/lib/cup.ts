import { supabase } from './supabase'

export const DEFAULT_CUP_REWARDS = {
  winner: 30,
  finalist: 20,
  semiFinalist: 10,
} as const

export const MINIMUM_CUP_PARTICIPANTS = 8

export const UNKNOWN_PLAYER_NAME = 'Άγνωστος παίκτης'

export const CUP_ROUND_META = {
  1: { name: '1ος Γύρος', matchdayNumber: 3 },
  2: { name: '2ος Γύρος', matchdayNumber: 4 },
  3: { name: '3ος Γύρος', matchdayNumber: 5 },
  4: { name: 'Προημιτελικά', matchdayNumber: 6 },
  5: { name: 'Ημιτελικά', matchdayNumber: 7 },
  6: { name: 'Τελικός', matchdayNumber: 8 },
} as const

export type CupRoundNumber = keyof typeof CUP_ROUND_META

export const CUP_ROUND_NUMBERS: CupRoundNumber[] = [1, 2, 3, 4, 5, 6]

export type CupRewards = {
  winner: number
  finalist: number
  semiFinalist: number
}

export type CupCompetition = {
  id: number
  slug: string
  season_label: string
  participant_count: number
  status: 'active' | 'completed'
  winner_points: number
  finalist_points: number
  semi_finalist_points: number
  created_at: string
}

export type CupParticipant = {
  id: number
  cup_id: number
  user_id: string | null
  username_snapshot: string
  rank_position: number
  bracket_position: number
  entry_round: number
}

export type CupRoundStatus = 'pending' | 'in_progress' | 'final'

export type CupRound = {
  id: number
  cup_id: number
  round_number: number
  matchday_id: number
  status: CupRoundStatus
}

export type CupTieOutcome = 'empty' | 'bye' | 'pending' | 'decided'

export type CupDecidedByRule = 'points' | 'exact' | 'correct' | 'rank_position'

export type CupTie = {
  id: number
  cup_id: number
  round_id: number
  slot: number
  home_participant_id: number | null
  away_participant_id: number | null
  home_points: number
  away_points: number
  home_exact: number
  away_exact: number
  home_correct: number
  away_correct: number
  winner_participant_id: number | null
  outcome: CupTieOutcome
  decided_by_rule: CupDecidedByRule | null
}

export type CupAwardType = 'winner' | 'finalist' | 'semi_finalist'

export type CupAward = {
  id: number
  cup_id: number
  participant_id: number
  user_id: string | null
  award_type: CupAwardType
  points: number
  created_at: string
  updated_at: string
}

export type CupExcludedMatch = {
  id: number
  cup_id: number
  round_id: number
  match_id: number
  cutoff_at: string
  excluded_at: string
}

export type CupMatchdayInfo = {
  id: number
  matchday_number: number | null
  name: string
}

export type CupPathRow = {
  round: CupRound
  tie: CupTie
}

type RankingMatch = {
  id: number
  status: string
}

type RankingMatchday = {
  id: number
  stage: string
  matchday_number: number | null
  name: string
  matches: RankingMatch[] | null
}

export type PlayersCupSnapshot = {
  cup: CupCompetition | null
  rankingMatchdaysExist: boolean
  rankingMatchdaysComplete: boolean
  activePlayerCount: number
  viewerRank: number | null
  viewerUserId: string | null
  rewards: CupRewards
  participants: CupParticipant[]
  rounds: CupRound[]
  ties: CupTie[]
  awards: CupAward[]
  excludedMatches: CupExcludedMatch[]
  matchdaysById: Record<number, CupMatchdayInfo>
}

const isMatchdayComplete = (matches: RankingMatch[] | null | undefined) => {
  if (!matches || matches.length === 0) {
    return false
  }

  return matches.every((match) => match.status === 'finished')
}

export const rewardsFromCompetition = (
  cup: CupCompetition | null,
): CupRewards => {
  if (!cup) {
    return {
      winner: DEFAULT_CUP_REWARDS.winner,
      finalist: DEFAULT_CUP_REWARDS.finalist,
      semiFinalist: DEFAULT_CUP_REWARDS.semiFinalist,
    }
  }

  return {
    winner: cup.winner_points,
    finalist: cup.finalist_points,
    semiFinalist: cup.semi_finalist_points,
  }
}

export const formatRankPosition = (rank: number) => `${rank}η`

export const isCupRoundNumber = (value: number): value is CupRoundNumber =>
  value === 1 ||
  value === 2 ||
  value === 3 ||
  value === 4 ||
  value === 5 ||
  value === 6

export const cupRoundName = (roundNumber: number) =>
  isCupRoundNumber(roundNumber)
    ? CUP_ROUND_META[roundNumber].name
    : `Γύρος ${roundNumber}`

export const cupRoundMatchdaySubtitle = (
  roundNumber: number,
  matchday?: CupMatchdayInfo | null,
) => {
  const matchdayNumber =
    matchday?.matchday_number ??
    (isCupRoundNumber(roundNumber)
      ? CUP_ROUND_META[roundNumber].matchdayNumber
      : null)

  if (matchdayNumber) {
    return `${matchdayNumber}η αγωνιστική`
  }

  return matchday?.name ?? ''
}

export const cupRoundStatusLabel = (status: CupRoundStatus) => {
  if (status === 'in_progress') return 'Σε εξέλιξη'
  if (status === 'final') return 'Ολοκληρώθηκε'
  return 'Αναμονή'
}

export const decidedByRuleLabel = (rule: string | null | undefined) => {
  if (rule === 'points') return 'Στα σημεία'
  if (rule === 'exact') return 'Με περισσότερα ακριβή σκορ'
  if (rule === 'correct') return 'Με περισσότερα σωστά αποτελέσματα'
  if (rule === 'rank_position') {
    return 'Με καλύτερη θέση μετά τη 2η αγωνιστική'
  }

  return null
}

export const isSeededRank = (rankPosition: number) =>
  rankPosition >= 1 && rankPosition <= 8

export const participantsById = (participants: CupParticipant[]) =>
  new Map(participants.map((participant) => [participant.id, participant]))

export const participantDisplayName = (
  participant: CupParticipant | undefined,
) => {
  const name = participant?.username_snapshot?.trim()

  return name ? name : UNKNOWN_PLAYER_NAME
}

export const findViewerParticipant = (
  participants: CupParticipant[],
  userId: string | null,
) => {
  if (!userId) return null

  return (
    participants.find((participant) => participant.user_id === userId) ?? null
  )
}

export const isVisibleTie = (tie: CupTie) => tie.outcome !== 'empty'

export const participantAppearsInTie = (
  tie: CupTie,
  participantId: number,
) =>
  tie.home_participant_id === participantId ||
  tie.away_participant_id === participantId

export const visibleTiesForRound = (ties: CupTie[], roundId: number) =>
  ties
    .filter((tie) => tie.round_id === roundId && isVisibleTie(tie))
    .sort((left, right) => left.slot - right.slot)

export const defaultSelectedRoundNumber = (
  rounds: CupRound[],
  ties: CupTie[],
  cupStatus?: CupCompetition['status'] | null,
) => {
  const ordered = [...rounds].sort(
    (left, right) => left.round_number - right.round_number,
  )

  if (cupStatus === 'completed') {
    const completed = ordered.filter((round) => round.status === 'final')

    if (completed.length > 0) {
      return completed[completed.length - 1].round_number
    }
  }

  const inProgress = ordered.find((round) => round.status === 'in_progress')

  if (inProgress) {
    return inProgress.round_number
  }

  const pendingWithTie = ordered.find((round) => {
    if (round.status !== 'pending') return false

    return ties.some(
      (tie) => tie.round_id === round.id && isVisibleTie(tie),
    )
  })

  if (pendingWithTie) {
    return pendingWithTie.round_number
  }

  const completed = ordered.filter((round) => round.status === 'final')

  if (completed.length > 0) {
    return completed[completed.length - 1].round_number
  }

  return 1
}

export const selectPersonalTie = (
  viewerParticipantId: number,
  selectedRoundId: number | null,
  rounds: CupRound[],
  ties: CupTie[],
) => {
  if (selectedRoundId !== null) {
    const selectedTie = ties.find(
      (tie) =>
        tie.round_id === selectedRoundId &&
        isVisibleTie(tie) &&
        participantAppearsInTie(tie, viewerParticipantId),
    )

    if (selectedTie) {
      return selectedTie
    }
  }

  const roundNumberById = new Map(
    rounds.map((round) => [round.id, round.round_number]),
  )

  const latest = ties
    .filter(
      (tie) =>
        isVisibleTie(tie) &&
        participantAppearsInTie(tie, viewerParticipantId),
    )
    .sort((left, right) => {
      const leftRound = roundNumberById.get(left.round_id) ?? 0
      const rightRound = roundNumberById.get(right.round_id) ?? 0

      if (leftRound !== rightRound) {
        return rightRound - leftRound
      }

      return right.slot - left.slot
    })

  return latest[0] ?? null
}

export const nextRoundName = (roundNumber: number) => {
  if (!isCupRoundNumber(roundNumber) || roundNumber === 6) {
    return null
  }

  return cupRoundName(roundNumber + 1)
}

export const cupLiveDataIsComplete = (snapshot: PlayersCupSnapshot) =>
  Boolean(snapshot.cup) &&
  snapshot.rounds.length > 0 &&
  snapshot.ties.length > 0

export const getViewerCupPath = (
  viewerParticipantId: number,
  rounds: CupRound[],
  ties: CupTie[],
) => {
  const roundById = new Map(rounds.map((round) => [round.id, round]))

  const appearances = ties
    .filter(
      (tie) =>
        isVisibleTie(tie) &&
        participantAppearsInTie(tie, viewerParticipantId),
    )
    .map((tie) => {
      const round = roundById.get(tie.round_id)

      if (!round) return null

      return { round, tie }
    })
    .filter((row): row is CupPathRow => row !== null)
    .sort((left, right) => {
      if (left.round.round_number !== right.round.round_number) {
        return left.round.round_number - right.round.round_number
      }

      return left.tie.slot - right.tie.slot
    })

  const path: CupPathRow[] = []

  for (const row of appearances) {
    path.push(row)

    if (
      row.tie.outcome === 'decided' &&
      row.tie.winner_participant_id !== viewerParticipantId
    ) {
      break
    }
  }

  return path
}

export const getCupHonours = (awards: CupAward[]) => {
  const winner =
    awards.find((award) => award.award_type === 'winner') ?? null
  const finalist =
    awards.find((award) => award.award_type === 'finalist') ?? null
  const semiFinalists = awards.filter(
    (award) => award.award_type === 'semi_finalist',
  )

  return { winner, finalist, semiFinalists }
}

export const getExcludedCountForRound = (
  excludedMatches: CupExcludedMatch[],
  roundId: number | null,
) => {
  if (roundId === null) return 0

  return excludedMatches.filter((row) => row.round_id === roundId).length
}

export const cupAwardLabel = (awardType: CupAwardType) => {
  if (awardType === 'winner') return 'Πρωταθλητής'
  if (awardType === 'finalist') return 'Φιναλίστ'
  return 'Ημιτελικά'
}

const emptyLiveState = {
  participants: [] as CupParticipant[],
  rounds: [] as CupRound[],
  ties: [] as CupTie[],
  awards: [] as CupAward[],
  excludedMatches: [] as CupExcludedMatch[],
  matchdaysById: {} as Record<number, CupMatchdayInfo>,
}

export const loadPlayersCupSnapshot = async (): Promise<{
  snapshot: PlayersCupSnapshot | null
  error: string | null
}> => {
  const [cupResult, matchdaysResult, profilesResult, userResult] =
    await Promise.all([
      supabase
        .from('cup_competitions')
        .select(
          'id, slug, season_label, participant_count, status, winner_points, finalist_points, semi_finalist_points, created_at',
        )
        .limit(1)
        .maybeSingle(),
      supabase
        .from('matchdays')
        .select(
          `
            id,
            stage,
            matchday_number,
            name,
            matches (
              id,
              status
            )
          `,
        )
        .eq('stage', 'league_phase')
        .in('matchday_number', [1, 2, 3, 4, 5, 6, 7, 8]),
      supabase
        .from('profiles')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'active'),
      supabase.auth.getUser(),
    ])

  if (cupResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκε το Κύπελλο: ${cupResult.error.message}`,
    }
  }

  if (matchdaysResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκαν οι αγωνιστικές του Κυπέλλου: ${matchdaysResult.error.message}`,
    }
  }

  if (profilesResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκαν οι ενεργοί παίκτες: ${profilesResult.error.message}`,
    }
  }

  const cup = (cupResult.data as CupCompetition | null) ?? null
  const matchdays = (matchdaysResult.data ?? []) as RankingMatchday[]
  const matchdayOne = matchdays.find(
    (matchday) => matchday.matchday_number === 1,
  )
  const matchdayTwo = matchdays.find(
    (matchday) => matchday.matchday_number === 2,
  )
  const matchdaysById = Object.fromEntries(
    matchdays.map((matchday) => [
      matchday.id,
      {
        id: matchday.id,
        matchday_number: matchday.matchday_number,
        name: matchday.name,
      },
    ]),
  ) as Record<number, CupMatchdayInfo>

  let viewerRank: number | null = null
  const viewerUserId = userResult.data.user?.id ?? null

  if (viewerUserId) {
    const { data: leaderboardData, error: leaderboardError } =
      await supabase.rpc('get_leaderboard')

    if (!leaderboardError) {
      const viewer = (
        (leaderboardData ?? []) as Array<{
          user_id: string
          rank_position: number
        }>
      ).find((row) => row.user_id === viewerUserId)

      viewerRank = viewer?.rank_position ?? null
    }
  }

  const baseSnapshot: PlayersCupSnapshot = {
    cup,
    rankingMatchdaysExist: Boolean(matchdayOne && matchdayTwo),
    rankingMatchdaysComplete:
      isMatchdayComplete(matchdayOne?.matches) &&
      isMatchdayComplete(matchdayTwo?.matches),
    activePlayerCount: profilesResult.count ?? 0,
    viewerRank,
    viewerUserId,
    rewards: rewardsFromCompetition(cup),
    ...emptyLiveState,
    matchdaysById,
  }

  if (!cup) {
    return { snapshot: baseSnapshot, error: null }
  }

  const [
    participantsResult,
    roundsResult,
    tiesResult,
    awardsResult,
    excludedResult,
  ] = await Promise.all([
    supabase
      .from('cup_participants')
      .select(
        'id, cup_id, user_id, username_snapshot, rank_position, bracket_position, entry_round',
      )
      .eq('cup_id', cup.id),
    supabase
      .from('cup_rounds')
      .select('id, cup_id, round_number, matchday_id, status')
      .eq('cup_id', cup.id)
      .order('round_number'),
    supabase
      .from('cup_ties')
      .select(
        'id, cup_id, round_id, slot, home_participant_id, away_participant_id, home_points, away_points, home_exact, away_exact, home_correct, away_correct, winner_participant_id, outcome, decided_by_rule',
      )
      .eq('cup_id', cup.id),
    supabase
      .from('cup_awards')
      .select(
        'id, cup_id, participant_id, user_id, award_type, points, created_at, updated_at',
      )
      .eq('cup_id', cup.id),
    supabase
      .from('cup_excluded_matches')
      .select('id, cup_id, round_id, match_id, cutoff_at, excluded_at')
      .eq('cup_id', cup.id),
  ])

  if (participantsResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκαν οι συμμετέχοντες του Κυπέλλου: ${participantsResult.error.message}`,
    }
  }

  if (roundsResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκαν οι γύροι του Κυπέλλου: ${roundsResult.error.message}`,
    }
  }

  if (tiesResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκαν οι αγώνες του Κυπέλλου: ${tiesResult.error.message}`,
    }
  }

  if (awardsResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκαν τα έπαθλα του Κυπέλλου: ${awardsResult.error.message}`,
    }
  }

  if (excludedResult.error) {
    return {
      snapshot: null,
      error: `Δεν φορτώθηκαν οι αναβληθέντες αγώνες του Κυπέλλου: ${excludedResult.error.message}`,
    }
  }

  return {
    snapshot: {
      ...baseSnapshot,
      participants: (participantsResult.data ?? []) as CupParticipant[],
      rounds: (roundsResult.data ?? []) as CupRound[],
      ties: (tiesResult.data ?? []) as CupTie[],
      awards: (awardsResult.data ?? []) as CupAward[],
      excludedMatches: (excludedResult.data ?? []) as CupExcludedMatch[],
    },
    error: null,
  }
}
