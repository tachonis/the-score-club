import { useCallback, useEffect, useState } from 'react'
import { AppHeader, type AppDestination } from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { supabase } from '../lib/supabase'

type LeaguePhasePageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type LeagueStanding = {
  position: number
  team_id: number
  team_name: string
  short_name: string | null
  logo_url: string | null
  country: string | null
  played: number
  wins: number
  draws: number
  losses: number
  goals_for: number
  goals_against: number
  goal_difference: number
  points: number
}

const formatGoalDifference = (value: number) => {
  if (value > 0) return `+${value}`
  return String(value)
}

export function LeaguePhasePage({
  username,
  role,
  onNavigate,
  onLogout,
}: LeaguePhasePageProps) {
  const [rows, setRows] = useState<LeagueStanding[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null)

  const loadStandings = useCallback(async (showLoading = false) => {
    if (showLoading) {
      setLoading(true)
    } else {
      setRefreshing(true)
    }

    setErrorMessage('')

    const { data, error } = await supabase
      .from('league_phase_standings')
      .select('*')
      .order('position', { ascending: true })

    if (error) {
      setErrorMessage(
        `Δεν φορτώθηκε η κατάταξη League Phase: ${error.message}`,
      )
    } else {
      setRows((data ?? []) as LeagueStanding[])
      setLastUpdated(new Date())
    }

    setLoading(false)
    setRefreshing(false)
  }, [])

  useEffect(() => {
    void loadStandings(true)

    const refreshInterval = window.setInterval(() => {
      void loadStandings()
    }, 30_000)

    const refreshOnFocus = () => {
      void loadStandings()
    }

    window.addEventListener('focus', refreshOnFocus)

    return () => {
      window.clearInterval(refreshInterval)
      window.removeEventListener('focus', refreshOnFocus)
    }
  }, [loadStandings])

  const finishedMatches = rows.reduce(
    (total, row) => total + row.played,
    0,
  ) / 2

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="league-phase"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="league-phase-main">
        <section className="league-phase-intro">
          <div>
            <p className="dashboard-eyebrow">Champions League 2026/27</p>
            <h1>League Phase</h1>
            <p>
              Η ζωντανή κατάταξη των 36 ομάδων, υπολογισμένη αποκλειστικά
              από ολοκληρωμένους αγώνες της League Phase.
            </p>
          </div>

          <div className="league-phase-summary" aria-label="Σύνοψη κατάταξης">
            <span>
              <strong>{rows.length || 36}</strong>
              ομάδες
            </span>
            <span>
              <strong>{finishedMatches}</strong>
              {finishedMatches === 1
                ? 'ολοκληρωμένος αγώνας'
                : 'ολοκληρωμένοι αγώνες'}
            </span>
          </div>
        </section>

        {errorMessage && (
          <p className="auth-message error">{errorMessage}</p>
        )}

        {loading ? (
          <section className="app-loading-inline">
            <LoadingMark />
            <p>Υπολογισμός κατάταξης...</p>
          </section>
        ) : (
          <section className="league-table-card">
            <div className="league-table-toolbar">
              <div>
                <span>{formatGreekAllCaps('Επίσημη κατάταξη')}</span>
                <strong>{finishedMatches} / 144 αγώνες ολοκληρώθηκαν</strong>
              </div>

              <button
                type="button"
                className="league-refresh-button"
                onClick={() => void loadStandings()}
                disabled={refreshing}
              >
                {refreshing ? 'Ανανέωση...' : 'Ανανέωση'}
              </button>
            </div>

            <div className="league-table-scroll" tabIndex={0}>
              <table className="league-table">
                <caption>
                  Κατάταξη League Phase με αγώνες, αποτελέσματα, γκολ και βαθμούς
                </caption>
                <thead>
                  <tr>
                    <th scope="col">Θέση</th>
                    <th scope="col">Ομάδα</th>
                    <th scope="col" title="Αγώνες">ΑΓ</th>
                    <th scope="col" title="Νίκες">Ν</th>
                    <th scope="col" title="Ισοπαλίες">Ι</th>
                    <th scope="col" title="Ήττες">Η</th>
                    <th scope="col" title="Γκολ υπέρ">ΓΥ</th>
                    <th scope="col" title="Γκολ κατά">ΓΚ</th>
                    <th scope="col" title="Διαφορά γκολ">ΔΓ</th>
                    <th scope="col" title="Βαθμοί">Β</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={row.team_id}>
                      <td className="league-position">{row.position}</td>
                      <th scope="row" className="league-team-cell">
                        <span className="league-team-mark" aria-hidden="true">
                          {row.logo_url ? (
                            <img src={row.logo_url} alt="" />
                          ) : (
                            row.short_name?.slice(0, 3) ??
                            row.team_name.slice(0, 3).toUpperCase()
                          )}
                        </span>
                        <span>
                          <strong>{row.team_name}</strong>
                          <small>{row.country ?? row.short_name}</small>
                        </span>
                      </th>
                      <td>{row.played}</td>
                      <td>{row.wins}</td>
                      <td>{row.draws}</td>
                      <td>{row.losses}</td>
                      <td>{row.goals_for}</td>
                      <td>{row.goals_against}</td>
                      <td>{formatGoalDifference(row.goal_difference)}</td>
                      <td className="league-points">{row.points}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <footer className="league-table-footer">
              <span>
                3 βαθμοί η νίκη · 1 η ισοπαλία · 0 η ήττα
              </span>
              {lastUpdated && (
                <span>
                  Τελευταία ενημέρωση{' '}
                  {lastUpdated.toLocaleTimeString('el-GR', {
                    hour: '2-digit',
                    minute: '2-digit',
                  })}
                </span>
              )}
            </footer>
          </section>
        )}

        <p className="league-tiebreak-note">
          <strong>Σειρά κατάταξης:</strong> βαθμοί, διαφορά γκολ, γκολ υπέρ.
          Για πλήρως ισόβαθμες ομάδες χρησιμοποιείται σταθερή αλφαβητική σειρά.
        </p>
      </main>

    </div>
  )
}
