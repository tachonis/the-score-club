import { useEffect, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { supabase } from '../lib/supabase'

type StandingsPageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type LeaderboardRow = {
  rank_position: number
  user_id: string
  username: string
  total_points: number
  exact_scores: number
  correct_results: number
  knockout_points: number
  missed_predictions: number
}

export function StandingsPage({
  username,
  role,
  onNavigate,
  onLogout,
}: StandingsPageProps) {
  const [rows, setRows] = useState<LeaderboardRow[]>([])
  const [currentUserId, setCurrentUserId] = useState('')
  const [loading, setLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState('')

  useEffect(() => {
    const loadLeaderboard = async () => {
      setLoading(true)
      setErrorMessage('')

      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser()

      if (userError || !user) {
        setErrorMessage('Δεν ήταν δυνατή η αναγνώριση του χρήστη.')
        setLoading(false)
        return
      }

      setCurrentUserId(user.id)

      const { data, error } = await supabase.rpc('get_leaderboard')

      if (error) {
        setErrorMessage(
          `Δεν φορτώθηκε η βαθμολογία: ${error.message}`,
        )
        setLoading(false)
        return
      }

      setRows((data ?? []) as LeaderboardRow[])
      setLoading(false)
    }

    void loadLeaderboard()
  }, [])

  const renderRank = (rank: number) => {
    if (rank === 1) return '🥇'
    if (rank === 2) return '🥈'
    if (rank === 3) return '🥉'

    return rank
  }

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="standings"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="tsc-standings-main">
        <section className="tsc-standings-intro">
          <p className="dashboard-eyebrow">
            Champions League 2026/27
          </p>

          <h1>Βαθμολογία</h1>

          <p>
            Η συνολική κατάταξη των παικτών του The Score Club.
          </p>
        </section>

        {errorMessage && (
          <p className="auth-message error">{errorMessage}</p>
        )}

        {loading ? (
          <section className="app-loading-inline">
            <div className="loading-mark">TSC</div>
            <p>Φόρτωση βαθμολογίας...</p>
          </section>
        ) : (
          <section className="tsc-leaderboard">
            <div className="tsc-leaderboard-top">
              <div>
                <span className="tsc-leaderboard-label">
                  Γενική κατάταξη
                </span>

                <strong>
                  {rows.length}{' '}
                  {rows.length === 1 ? 'παίκτης' : 'παίκτες'}
                </strong>
              </div>

              <span className="tsc-season-badge">
                League Phase
              </span>
            </div>

            <div className="tsc-table-scroll">
              <div className="tsc-table-header">
                <span>Θέση</span>
                <span>Παίκτης</span>
                <span>Βαθμοί</span>
                <span>Ακριβή</span>
                <span>Σωστά</span>
              </div>

              <div className="tsc-table-body">
                {rows.length === 0 ? (
                  <div className="tsc-leaderboard-empty">
                    Δεν υπάρχουν ακόμη παίκτες στη βαθμολογία.
                  </div>
                ) : (
                  rows.map((row) => {
                    const isCurrentUser =
                      row.user_id === currentUserId

                    return (
                      <article
                        key={row.user_id}
                        className={`tsc-table-row ${
                          isCurrentUser ? 'is-me' : ''
                        }`}
                      >
                        <div className="tsc-rank">
                          {renderRank(row.rank_position)}
                        </div>

                        <div className="tsc-player">
                          <div className="tsc-player-avatar">
                            {row.username
                              .charAt(0)
                              .toUpperCase()}
                          </div>

                          <div>
                            <strong>{row.username}</strong>

                            {isCurrentUser && (
                              <small>Εσύ</small>
                            )}
                          </div>
                        </div>

                        <div className="tsc-points">
                          {row.total_points}
                        </div>

                        <div className="tsc-stat">
                          {row.exact_scores}
                        </div>

                        <div className="tsc-stat">
                          {row.correct_results}
                        </div>
                      </article>
                    )
                  })
                )}
              </div>
            </div>
          </section>
        )}

        <div className="tsc-tiebreak-note">
          <strong>Ισοβαθμία:</strong> προηγούνται τα περισσότερα
          ακριβή σκορ και στη συνέχεια τα περισσότερα σωστά
          αποτελέσματα.
        </div>
      </main>

    </div>
  )
}
