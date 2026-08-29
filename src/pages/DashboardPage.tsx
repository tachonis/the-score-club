import { useEffect, useMemo, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { PushNotificationsCard } from '../components/PushNotificationsCard'
import { LoadingMark } from '../components/BrandAssets'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import {
  compareMatchdays,
  getMatchdayRoundLabel,
  getStageLabel,
  isFinalStage,
  isLeaguePhaseStage,
} from '../lib/stages'
import { supabase } from '../lib/supabase'

type DashboardPageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type Matchday = {
  id: number
  stage: string
  matchday_number: number | null
  name: string
  starts_at: string | null
  ends_at: string | null
  status: 'upcoming' | 'active' | 'completed'
}

type Match = {
  id: number
  kickoff_at: string
  status:
    | 'scheduled'
    | 'live'
    | 'finished'
    | 'postponed'
    | 'cancelled'
}

type MatchdayWithMatches = Matchday & {
  matches: Match[]
}

/** A matchday is complete only when it has matches and every match is finished. */
const isMatchdayComplete = (matchdayMatches: Match[]) => {
  if (matchdayMatches.length === 0) {
    return false
  }

  return matchdayMatches.every((match) => match.status === 'finished')
}

const isMatchLocked = (match: Match, now: number) => {
  return (
    match.status !== 'scheduled' ||
    now >= new Date(match.kickoff_at).getTime()
  )
}

const selectCurrentMatchday = (
  matchdays: MatchdayWithMatches[],
): { matchday: Matchday; matches: Match[]; allComplete: boolean } | null => {
  const orderedMatchdays = [...matchdays].sort(compareMatchdays)
  const populated = orderedMatchdays.filter(
    (matchday) => (matchday.matches ?? []).length > 0,
  )

  if (populated.length === 0) {
    return null
  }

  const withSortedMatches = populated.map((matchday) => ({
    matchday,
    matches: [...(matchday.matches ?? [])].sort(
      (left, right) =>
        new Date(left.kickoff_at).getTime() -
        new Date(right.kickoff_at).getTime(),
    ),
  }))

  const incomplete = withSortedMatches.find(
    ({ matches }) => !isMatchdayComplete(matches),
  )

  if (incomplete) {
    return { ...incomplete, allComplete: false }
  }

  const latest = withSortedMatches[withSortedMatches.length - 1]
  return { ...latest, allComplete: true }
}

type Prediction = {
  match_id: number
}

type PlayerStats = {
  rank_position: number
  user_id: string
  total_points: number
  exact_scores: number
  correct_results: number
}

export function DashboardPage({
  username,
  role,
  onNavigate,
  onLogout,
}: DashboardPageProps) {
  const [nextMatchday, setNextMatchday] =
    useState<Matchday | null>(null)
  const [roundComplete, setRoundComplete] = useState(false)

  const [matches, setMatches] = useState<Match[]>([])
  const [predictions, setPredictions] = useState<Prediction[]>([])
  const [playerStats, setPlayerStats] = useState<PlayerStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')

  useEffect(() => {
    const loadDashboard = async () => {
      setLoading(true)
      setLoadError('')

      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser()

      if (userError || !user) {
        setLoadError('Δεν ήταν δυνατή η αναγνώριση του χρήστη.')
        setLoading(false)
        return
      }

      const { data: leaderboardData, error: leaderboardError } =
        await supabase.rpc('get_leaderboard')

      if (leaderboardError) {
        setLoadError(
          `Δεν φορτώθηκαν τα στοιχεία βαθμολογίας: ${leaderboardError.message}`,
        )
        setLoading(false)
        return
      }

      const currentPlayerStats = (
        (leaderboardData ?? []) as PlayerStats[]
      ).find((row) => row.user_id === user.id)

      setPlayerStats(currentPlayerStats ?? null)

      const { data: matchdaysData, error: matchdayError } =
        await supabase
          .from('matchdays')
          .select(`
            id,
            stage,
            matchday_number,
            name,
            starts_at,
            ends_at,
            status,
            matches (
              id,
              kickoff_at,
              status
            )
          `)

      if (matchdayError) {
        setLoadError(
          `Δεν φορτώθηκαν οι επόμενοι αγώνες: ${matchdayError.message}`,
        )
        setLoading(false)
        return
      }

      const selected = selectCurrentMatchday(
        (matchdaysData ?? []) as MatchdayWithMatches[],
      )

      if (!selected) {
        setNextMatchday(null)
        setRoundComplete(false)
        setMatches([])
        setPredictions([])
        setLoading(false)
        return
      }

      const loadedMatchday = selected.matchday
      const loadedMatches = selected.matches

      setNextMatchday(loadedMatchday)
      setRoundComplete(selected.allComplete)
      setMatches(loadedMatches)

      const matchIds = loadedMatches.map((match) => match.id)

      if (matchIds.length === 0) {
        setPredictions([])
        setLoading(false)
        return
      }

      const { data: predictionsData, error: predictionsError } =
        await supabase
          .from('predictions')
          .select('match_id')
          .eq('user_id', user.id)
          .in('match_id', matchIds)

      if (predictionsError) {
        setLoadError(
          `Δεν φορτώθηκαν οι προβλέψεις: ${predictionsError.message}`,
        )
        setLoading(false)
        return
      }

      setPredictions((predictionsData ?? []) as Prediction[])
      setLoading(false)
    }

    void loadDashboard()
  }, [])

  const totalMatches = matches.length
  const savedPredictions = predictions.length

  const progressPercentage = useMemo(() => {
    if (totalMatches === 0) {
      return 0
    }

    return Math.round((savedPredictions / totalMatches) * 100)
  }, [savedPredictions, totalMatches])

  const nextKickoff = matches[0]?.kickoff_at ?? null
  const now = Date.now()
  const allFinished =
    matches.length > 0 &&
    matches.every((match) => match.status === 'finished')
  const allLocked =
    matches.length > 0 &&
    matches.every((match) => isMatchLocked(match, now))
  const stageLabel = nextMatchday ? getStageLabel(nextMatchday.stage) : ''
  const roundLabel = nextMatchday
    ? getMatchdayRoundLabel(
        nextMatchday.stage,
        nextMatchday.matchday_number,
        nextMatchday.name,
      )
    : ''
  const showRoundSubtitle =
    roundLabel !== '' &&
    roundLabel !== stageLabel &&
    !isFinalStage(nextMatchday?.stage ?? '')
  const eyebrowLabel = () => {
    if (!nextMatchday) {
      return 'Επόμενοι αγώνες'
    }

    if (roundComplete || allFinished) {
      return 'Ολοκληρωμένοι αγώνες'
    }

    if (isLeaguePhaseStage(nextMatchday.stage)) {
      return 'Επόμενη αγωνιστική'
    }

    return 'Επόμενοι αγώνες'
  }

  const formatDate = (dateValue: string) => {
    return new Intl.DateTimeFormat('el-GR', {
      weekday: 'long',
      day: '2-digit',
      month: 'long',
      year: 'numeric',
    }).format(new Date(dateValue))
  }

  const formatTime = (dateValue: string) => {
    return new Intl.DateTimeFormat('el-GR', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(dateValue))
  }

  const matchdayStatusLabel = () => {
    if (!nextMatchday) {
      return 'Δεν υπάρχουν αγώνες'
    }

    if (matches.length === 0) {
      return 'Δεν έχει ξεκινήσει'
    }

    if (allFinished) {
      return 'Ολοκληρώθηκε'
    }

    if (allLocked) {
      return 'Κλειδωμένο'
    }

    const allScheduled = matches.every(
      (match) => match.status === 'scheduled',
    )

    if (allScheduled) {
      return 'Δεν έχει ξεκινήσει'
    }

    return 'Σε εξέλιξη'
  }

  const roundDescription = () => {
    if (allFinished) {
      return 'Οι αγώνες αυτού του γύρου ολοκληρώθηκαν.'
    }

    if (allLocked) {
      return 'Οι προβλέψεις έχουν κλειδώσει.'
    }

    return 'Οι προβλέψεις κλειδώνουν ξεχωριστά με την έναρξη κάθε αγώνα. Μπορείς να τις αλλάξεις μέχρι τότε.'
  }

  const ctaLabel =
    totalMatches > 0 && (allLocked || allFinished || savedPredictions === totalMatches)
      ? 'Έλεγξε τις προβλέψεις σου'
      : 'Κάνε τις προβλέψεις σου'

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="home"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="dashboard-main">
        <section className="dashboard-welcome">
          <div>
            <p className="dashboard-eyebrow">
              Champions League 2026/27
            </p>

            <h1>Καλώς ήρθες, {username}</h1>

            <p>
              Κάνε τις προβλέψεις σου, συγκέντρωσε βαθμούς και
              διεκδίκησε την κορυφή του The Score Club.
            </p>
          </div>
        </section>

        {loadError && (
          <p className="auth-message error">{loadError}</p>
        )}

        <section
          className="player-summary"
          aria-label="Στοιχεία παίκτη"
        >
          <article className="summary-card">
            <span>Θέση</span>
            <strong>
              {loading ? '—' : (playerStats?.rank_position ?? '—')}
            </strong>
            <small>
              {playerStats
                ? 'Στη γενική κατάταξη'
                : 'Δεν υπάρχει ακόμη κατάταξη'}
            </small>
          </article>

          <article className="summary-card">
            <span>Συνολικοί βαθμοί</span>
            <strong>{loading ? '—' : (playerStats?.total_points ?? 0)}</strong>
            <small>
              {playerStats
                ? `${playerStats.exact_scores} ακριβή · ${playerStats.correct_results} σωστά`
                : 'Η βαθμολογία δεν έχει ξεκινήσει'}
            </small>
          </article>

          <article className="summary-card">
            <span>Προβλέψεις</span>

            <strong>
              {loading ? '—' : `${savedPredictions} / ${totalMatches}`}
            </strong>

            <small>
              {nextMatchday
                ? showRoundSubtitle
                  ? `${stageLabel} · ${roundLabel}`
                  : stageLabel
                : 'Δεν υπάρχει ενεργός γύρος'}
            </small>
          </article>
        </section>

        <PushNotificationsCard />

        {loading ? (
          <section className="dashboard-loading-card">
            <LoadingMark />
            <p>Φόρτωση αγώνων...</p>
          </section>
        ) : nextMatchday ? (
          <section className="next-matchday-card">
            <div className="matchday-info">
              <div className="matchday-heading-row">
                <div>
                  <p className="dashboard-eyebrow">
                    {formatGreekAllCaps(eyebrowLabel())}
                  </p>

                  <h2>{stageLabel}</h2>
                  {showRoundSubtitle && (
                    <p className="matchday-round-label">{roundLabel}</p>
                  )}
                </div>

                <span className="matchday-status">
                  {matchdayStatusLabel()}
                </span>
              </div>

              {nextKickoff ? (
                <p className="matchday-date">
                  Έναρξη: {formatDate(nextKickoff)} στις{' '}
                  {formatTime(nextKickoff)}
                </p>
              ) : (
                <p className="matchday-date">
                  Δεν έχουν προστεθεί ακόμη αγώνες.
                </p>
              )}

              <p className="matchday-description">
                {roundDescription()}
              </p>

              <div className="prediction-progress">
                <div className="progress-labels">
                  <span>Πρόοδος προβλέψεων</span>

                  <strong>
                    {savedPredictions} από {totalMatches}
                  </strong>
                </div>

                <div
                  className="progress-track"
                  role="progressbar"
                  aria-label="Πρόοδος προβλέψεων"
                  aria-valuemin={0}
                  aria-valuemax={totalMatches}
                  aria-valuenow={savedPredictions}
                >
                  <span
                    style={{
                      width: `${progressPercentage}%`,
                    }}
                  />
                </div>
              </div>

              <button
                type="button"
                className="predictions-button"
                onClick={() => onNavigate('predictions')}
                disabled={totalMatches === 0}
              >
                {ctaLabel}
              </button>
            </div>

            <div className="matchday-visual" aria-hidden="true">
              <div className="score-preview">
                <span className="score-team">HOME</span>

                <div className="score-boxes">
                  <span>—</span>
                  <small>:</small>
                  <span>—</span>
                </div>

                <span className="score-team">AWAY</span>
              </div>
            </div>
          </section>
        ) : (
          <section className="empty-state">
            <h2>Δεν υπάρχουν διαθέσιμοι αγώνες</h2>

            <p>
              Ο επόμενος γύρος θα εμφανιστεί όταν προστεθούν οι
              επίσημες αναμετρήσεις.
            </p>
          </section>
        )}
      </main>

    </div>
  )
}
