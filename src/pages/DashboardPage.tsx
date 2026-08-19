import { useEffect, useMemo, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { PushNotificationsCard } from '../components/PushNotificationsCard'
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

const selectNextMatchday = (
  matchdays: MatchdayWithMatches[],
): { matchday: Matchday; matches: Match[] } | null => {
  const orderedMatchdays = [...matchdays].sort((a, b) => {
    const numberDiff = (a.matchday_number ?? 0) - (b.matchday_number ?? 0)
    if (numberDiff !== 0) {
      return numberDiff
    }

    return a.id - b.id
  })

  for (const matchday of orderedMatchdays) {
    const matchdayMatches = [...(matchday.matches ?? [])].sort(
      (a, b) =>
        new Date(a.kickoff_at).getTime() - new Date(b.kickoff_at).getTime(),
    )

    if (!isMatchdayComplete(matchdayMatches)) {
      return { matchday, matches: matchdayMatches }
    }
  }

  return null
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
          .order('matchday_number', { ascending: true })

      if (matchdayError) {
        setLoadError(
          `Δεν φορτώθηκε η επόμενη αγωνιστική: ${matchdayError.message}`,
        )
        setLoading(false)
        return
      }

      const selected = selectNextMatchday(
        (matchdaysData ?? []) as MatchdayWithMatches[],
      )

      if (!selected) {
        setNextMatchday(null)
        setMatches([])
        setPredictions([])
        setLoading(false)
        return
      }

      const loadedMatchday = selected.matchday
      const loadedMatches = selected.matches

      setNextMatchday(loadedMatchday)
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
      return 'Δεν υπάρχει αγωνιστική'
    }

    if (matches.length === 0) {
      return 'Δεν έχει ξεκινήσει'
    }

    const allScheduled = matches.every(
      (match) => match.status === 'scheduled',
    )

    if (allScheduled) {
      return 'Δεν έχει ξεκινήσει'
    }

    return 'Σε εξέλιξη'
  }

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
              {nextMatchday?.name ?? 'Δεν υπάρχει ενεργή αγωνιστική'}
            </small>
          </article>
        </section>

        <PushNotificationsCard />

        {loading ? (
          <section className="dashboard-loading-card">
            <div className="loading-mark">TSC</div>
            <p>Φόρτωση αγωνιστικής...</p>
          </section>
        ) : nextMatchday ? (
          <section className="next-matchday-card">
            <div className="matchday-info">
              <div className="matchday-heading-row">
                <div>
                  <p className="dashboard-eyebrow">
                    Επόμενη αγωνιστική
                  </p>

                  <h2>{nextMatchday.name}</h2>
                </div>

                <span className="matchday-status">
                  {matchdayStatusLabel()}
                </span>
              </div>

              {nextKickoff ? (
                <p className="matchday-date">
                  Πρώτος αγώνας: {formatDate(nextKickoff)} στις{' '}
                  {formatTime(nextKickoff)}
                </p>
              ) : (
                <p className="matchday-date">
                  Δεν έχουν προστεθεί ακόμη αγώνες.
                </p>
              )}

              <p className="matchday-description">
                Οι προβλέψεις κλειδώνουν ξεχωριστά με την έναρξη
                κάθε αγώνα. Μπορείς να τις αλλάξεις μέχρι τότε.
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
                {savedPredictions === totalMatches &&
                totalMatches > 0
                  ? 'Έλεγξε τις προβλέψεις σου'
                  : 'Κάνε τις προβλέψεις σου'}
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
            <h2>Δεν υπάρχει επόμενη αγωνιστική</h2>

            <p>
              Η επόμενη αγωνιστική θα εμφανιστεί όταν προστεθεί
              από τη διαχείριση.
            </p>
          </section>
        )}
      </main>

    </div>
  )
}
