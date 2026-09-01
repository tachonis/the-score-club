import { useCallback, useEffect, useState } from 'react'
import { AppHeader, type AppDestination } from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { dateLocale, selectPlural, t } from '../i18n'
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
        t('errors.loadLeaguePhase', { detail: error.message }),
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
            <h1>{t('nav.leaguePhase')}</h1>
            <p>{t('league.intro')}</p>
          </div>

          <div className="league-phase-summary" aria-label={t('league.summaryAria')}>
            <span>
              <strong>{rows.length || 36}</strong>
              {t('league.teams')}
            </span>
            <span>
              <strong>{finishedMatches}</strong>
              {t(selectPlural(finishedMatches, 'league.finishedOne', 'league.finishedMany'))}
            </span>
          </div>
        </section>

        {errorMessage && (
          <p className="auth-message error">{errorMessage}</p>
        )}

        {loading ? (
          <section className="app-loading-inline">
            <LoadingMark />
            <p>{t('league.loading')}</p>
          </section>
        ) : (
          <section className="league-table-card">
            <div className="league-table-toolbar">
              <div>
                <span>{formatGreekAllCaps(t('league.official'))}</span>
                <strong>{t('league.finishedOf', { finished: finishedMatches })}</strong>
              </div>

              <button
                type="button"
                className="league-refresh-button"
                onClick={() => void loadStandings()}
                disabled={refreshing}
              >
                {refreshing ? t('common.refreshing') : t('common.refresh')}
              </button>
            </div>

            <div className="league-table-scroll" tabIndex={0}>
              <table className="league-table">
                <caption>{t('league.caption')}</caption>
                <thead>
                  <tr>
                    <th scope="col">{t('league.pos')}</th>
                    <th scope="col">{t('league.team')}</th>
                    <th scope="col" title={t('league.playedTitle')}>{t('league.played')}</th>
                    <th scope="col" title={t('league.winsTitle')}>{t('league.wins')}</th>
                    <th scope="col" title={t('league.drawsTitle')}>{t('league.draws')}</th>
                    <th scope="col" title={t('league.lossesTitle')}>{t('league.losses')}</th>
                    <th scope="col" title={t('league.gfTitle')}>{t('league.gf')}</th>
                    <th scope="col" title={t('league.gaTitle')}>{t('league.ga')}</th>
                    <th scope="col" title={t('league.gdTitle')}>{t('league.gd')}</th>
                    <th scope="col" title={t('league.ptsTitle')}>{t('league.pts')}</th>
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
              <span>{t('league.scoring')}</span>
              {lastUpdated && (
                <span>
                  {t('league.lastUpdated', {
                    time: lastUpdated.toLocaleTimeString(dateLocale, {
                      hour: '2-digit',
                      minute: '2-digit',
                    }),
                  })}
                </span>
              )}
            </footer>
          </section>
        )}

        <p className="league-tiebreak-note">
          <strong>{t('league.orderLead')}</strong> {t('league.orderRest')}
        </p>
      </main>

    </div>
  )
}
