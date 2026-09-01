import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { selectPlural, t } from '../i18n'
import { usePlayerProfileNav } from '../lib/playerProfileNav'
import {
  compareMatchdays,
  formatLeaguePhaseOrdinal,
  formatLeaguePhaseRound,
  isLeaguePhaseStage,
  selectDefaultLeaguePhaseMatchdayId,
} from '../lib/stages'
import { supabase } from '../lib/supabase'

type StandingsPageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type StandingsView = 'overall' | 'matchday' | 'knockout'

type LeaderboardRow = {
  rank_position: number
  user_id: string
  username: string
  total_points: number
  exact_scores: number
  correct_results: number
  knockout_points?: number
  missed_predictions?: number
}

type LeagueMatchday = {
  id: number
  stage: string
  matchday_number: number | null
  name: string
  matches: { id: number; status: string }[] | null
}

const VIEWS: { id: StandingsView; label: string }[] = [
  { id: 'overall', label: t('standings.overall') },
  { id: 'matchday', label: t('standings.byMatchday') },
  { id: 'knockout', label: t('standings.knockout') },
]

export function StandingsPage({
  username,
  role,
  onNavigate,
  onLogout,
}: StandingsPageProps) {
  const { openProfile } = usePlayerProfileNav()
  const [view, setView] = useState<StandingsView>('overall')
  const [overallRows, setOverallRows] = useState<LeaderboardRow[]>([])
  const [matchdayRows, setMatchdayRows] = useState<LeaderboardRow[]>([])
  const [knockoutRows, setKnockoutRows] = useState<LeaderboardRow[]>([])
  const [leagueMatchdays, setLeagueMatchdays] = useState<LeagueMatchday[]>(
    [],
  )
  const [selectedMatchdayId, setSelectedMatchdayId] = useState<number | null>(
    null,
  )
  const [currentUserId, setCurrentUserId] = useState('')
  const [loadingOverall, setLoadingOverall] = useState(true)
  const [loadingMatchdays, setLoadingMatchdays] = useState(false)
  const [loadingMatchdayBoard, setLoadingMatchdayBoard] = useState(false)
  const [loadingKnockout, setLoadingKnockout] = useState(false)
  const [loadedMatchdayId, setLoadedMatchdayId] = useState<number | null>(
    null,
  )
  const [matchdaysLoaded, setMatchdaysLoaded] = useState(false)
  const [knockoutLoaded, setKnockoutLoaded] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')
  const userPickedMatchdayRef = useRef(false)

  const orderedLeagueMatchdays = useMemo(
    () => [...leagueMatchdays].sort(compareMatchdays),
    [leagueMatchdays],
  )

  const selectedMatchday = orderedLeagueMatchdays.find(
    (matchday) => matchday.id === selectedMatchdayId,
  )

  useEffect(() => {
    const loadOverall = async () => {
      setLoadingOverall(true)
      setErrorMessage('')

      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser()

      if (userError || !user) {
        setErrorMessage(t('errors.identifyUser'))
        setLoadingOverall(false)
        return
      }

      setCurrentUserId(user.id)

      const { data, error } = await supabase.rpc('get_leaderboard')

      if (error) {
        setErrorMessage(
          t('errors.loadStandings', { detail: error.message }),
        )
        setLoadingOverall(false)
        return
      }

      setOverallRows((data ?? []) as LeaderboardRow[])
      setLoadingOverall(false)
    }

    void loadOverall()
  }, [])

  useEffect(() => {
    if (view !== 'matchday' || matchdaysLoaded) {
      return
    }

    const loadMatchdays = async () => {
      setLoadingMatchdays(true)
      setErrorMessage('')

      const { data, error } = await supabase
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

      if (error) {
        setErrorMessage(
          t('errors.loadMatchdays', { detail: error.message }),
        )
        setMatchdaysLoaded(true)
        setLoadingMatchdays(false)
        return
      }

      const loaded = ((data ?? []) as LeagueMatchday[]).filter((matchday) =>
        isLeaguePhaseStage(matchday.stage),
      )

      setMatchdaysLoaded(true)
      setLeagueMatchdays(loaded)

      if (!userPickedMatchdayRef.current) {
        setSelectedMatchdayId(selectDefaultLeaguePhaseMatchdayId(loaded))
      }

      setLoadingMatchdays(false)
    }

    void loadMatchdays()
  }, [view, matchdaysLoaded])

  useEffect(() => {
    if (view !== 'matchday' || selectedMatchdayId == null) {
      return
    }

    const loadMatchdayBoard = async () => {
      setLoadingMatchdayBoard(true)
      setErrorMessage('')

      const { data, error } = await supabase.rpc('get_matchday_leaderboard', {
        p_matchday_id: selectedMatchdayId,
      })

      if (error) {
        setErrorMessage(
          t('errors.loadMatchdayStandings', { detail: error.message }),
        )
        setMatchdayRows([])
        setLoadedMatchdayId(selectedMatchdayId)
        setLoadingMatchdayBoard(false)
        return
      }

      setMatchdayRows((data ?? []) as LeaderboardRow[])
      setLoadedMatchdayId(selectedMatchdayId)
      setLoadingMatchdayBoard(false)
    }

    void loadMatchdayBoard()
  }, [view, selectedMatchdayId])

  useEffect(() => {
    if (view !== 'knockout' || knockoutLoaded) {
      return
    }

    const loadKnockout = async () => {
      setLoadingKnockout(true)
      setErrorMessage('')

      const { data, error } = await supabase.rpc('get_knockout_leaderboard')

      if (error) {
        setErrorMessage(
          t('errors.loadKnockoutStandings', { detail: error.message }),
        )
        setKnockoutLoaded(true)
        setLoadingKnockout(false)
        return
      }

      setKnockoutLoaded(true)
      setKnockoutRows((data ?? []) as LeaderboardRow[])
      setLoadingKnockout(false)
    }

    void loadKnockout()
  }, [view, knockoutLoaded])

  const activeRows =
    view === 'matchday'
      ? matchdayRows
      : view === 'knockout'
        ? knockoutRows
        : overallRows

  const viewLoading =
    view === 'matchday'
      ? loadingMatchdays ||
        loadingMatchdayBoard ||
        (selectedMatchdayId != null && selectedMatchdayId !== loadedMatchdayId)
      : view === 'knockout'
        ? loadingKnockout
        : loadingOverall

  const showPodium = activeRows.some((row) => row.total_points > 0)

  const boardLabel =
    view === 'matchday'
      ? selectedMatchday?.matchday_number != null
        ? formatLeaguePhaseRound(selectedMatchday.matchday_number)
        : t('standings.byMatchdayBoard')
      : view === 'knockout'
        ? t('standings.knockout')
        : t('standings.overallBoard')

  const introCopy =
    view === 'matchday'
      ? t('standings.introMatchday')
      : view === 'knockout'
        ? t('standings.introKnockout')
        : t('standings.introOverall')

  const renderRank = (rank: number) => {
    if (showPodium) {
      if (rank === 1) return '🥇'
      if (rank === 2) return '🥈'
      if (rank === 3) return '🥉'
    }

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

          <h1>{t('standings.title')}</h1>

          <p>{introCopy}</p>
        </section>

        <div
          className="tsc-standings-views"
          role="tablist"
          aria-label={t('standings.viewsAria')}
        >
          {VIEWS.map((item) => {
            const selected = view === item.id

            return (
              <button
                key={item.id}
                type="button"
                role="tab"
                aria-selected={selected}
                className={`tsc-standings-view ${selected ? 'active' : ''}`}
                onClick={() => {
                  setErrorMessage('')

                  if (item.id === 'matchday' && !matchdaysLoaded) {
                    setLoadingMatchdays(true)
                  }

                  if (item.id === 'knockout' && !knockoutLoaded) {
                    setLoadingKnockout(true)
                  }

                  setView(item.id)
                }}
              >
                {item.label}
              </button>
            )
          })}
        </div>

        {view === 'matchday' && orderedLeagueMatchdays.length > 0 ? (
          <section className="matchday-selector tsc-standings-matchdays">
            <div
              className="matchday-tabs"
              role="tablist"
              aria-label={t('standings.matchdaysAria')}
            >
              {orderedLeagueMatchdays.map((matchday) => {
                const isSelected = selectedMatchdayId === matchday.id
                const ordinal =
                  matchday.matchday_number != null
                    ? formatLeaguePhaseOrdinal(matchday.matchday_number)
                    : matchday.name

                return (
                  <button
                    key={matchday.id}
                    type="button"
                    role="tab"
                    aria-selected={isSelected}
                    aria-label={
                      matchday.matchday_number != null
                        ? formatLeaguePhaseRound(matchday.matchday_number)
                        : matchday.name
                    }
                    className={`matchday-tab ${isSelected ? 'active' : ''}`}
                    onClick={() => {
                      userPickedMatchdayRef.current = true
                      setSelectedMatchdayId(matchday.id)
                    }}
                  >
                    {ordinal}
                  </button>
                )
              })}
            </div>
          </section>
        ) : null}

        {errorMessage && (
          <p className="auth-message error">{errorMessage}</p>
        )}

        {viewLoading ? (
          <section className="app-loading-inline">
            <LoadingMark />
            <p>{t('standings.loading')}</p>
          </section>
        ) : (
          <section className="tsc-leaderboard">
            <div className="tsc-leaderboard-top">
              <div>
                <span className="tsc-leaderboard-label">
                  {formatGreekAllCaps(boardLabel)}
                </span>

                <strong>
                  {activeRows.length}{' '}
                  {t(selectPlural(activeRows.length, 'standings.playerOne', 'standings.playerMany'))}
                </strong>
              </div>
            </div>

            <div className="tsc-table-scroll">
              <div className="tsc-table-header">
                <span>{formatGreekAllCaps(t('standings.pos'))}</span>
                <span>{formatGreekAllCaps(t('standings.player'))}</span>
                <span>{formatGreekAllCaps(t('standings.pts'))}</span>
                <span>{formatGreekAllCaps(t('standings.exact'))}</span>
                <span>{formatGreekAllCaps(t('standings.correct'))}</span>
              </div>

              <div className="tsc-table-body">
                {activeRows.length === 0 ? (
                  <div className="tsc-leaderboard-empty">
                    {t('standings.empty')}
                  </div>
                ) : (
                  activeRows.map((row) => {
                    const isCurrentUser = row.user_id === currentUserId

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
                            {row.username.charAt(0).toUpperCase()}
                          </div>

                          <button
                            type="button"
                            className="tsc-player-name"
                            onClick={() => openProfile(row.user_id)}
                            aria-label={t('nav.profileOf', { username: row.username })}
                          >
                            <span>{row.username}</span>
                            {isCurrentUser ? <small>{t('common.you')}</small> : null}
                          </button>
                        </div>

                        <div className="tsc-points">{row.total_points}</div>

                        <div className="tsc-stat">{row.exact_scores}</div>

                        <div className="tsc-stat">{row.correct_results}</div>
                      </article>
                    )
                  })
                )}
              </div>
            </div>
          </section>
        )}

        {view === 'overall' ? (
          <section
            className="tsc-tiebreak-note"
            aria-labelledby="standings-tiebreak-heading"
          >
            <h2 id="standings-tiebreak-heading">{t('standings.tiebreak')}</h2>
            <p>{t('standings.tiebreakApply')}</p>
            <ol>
              <li>{t('standings.tieExact')}</li>
              <li>{t('standings.tieCorrect')}</li>
              <li>{t('standings.tieKnockoutPts')}</li>
              <li>{t('standings.tieMissed')}</li>
            </ol>
            <p>{t('standings.tieShare')}</p>
            <p>{t('standings.knockoutPtsNote')}</p>
            <p>{t('standings.missedNote')}</p>
          </section>
        ) : null}

        {view === 'matchday' ? (
          <section
            className="tsc-tiebreak-note"
            aria-labelledby="standings-matchday-tiebreak-heading"
          >
            <h2 id="standings-matchday-tiebreak-heading">{t('standings.tiebreak')}</h2>
            <p>{t('standings.matchdayScope')}</p>
            <p>{t('standings.tiebreakApply')}</p>
            <ol>
              <li>{t('standings.tieExactMatchday')}</li>
              <li>{t('standings.tieCorrectMatchday')}</li>
            </ol>
            <p>{t('standings.tieShare')}</p>
          </section>
        ) : null}

        {view === 'knockout' ? (
          <section
            className="tsc-tiebreak-note"
            aria-labelledby="standings-knockout-tiebreak-heading"
          >
            <h2 id="standings-knockout-tiebreak-heading">{t('standings.tiebreak')}</h2>
            <p>{t('standings.knockoutScope')}</p>
            <p>{t('standings.tiebreakApply')}</p>
            <ol>
              <li>{t('standings.tieExactKnockout')}</li>
              <li>{t('standings.tieCorrectKnockout')}</li>
              <li>{t('standings.tieMissedKnockout')}</li>
            </ol>
            <p>{t('standings.tieShare')}</p>
          </section>
        ) : null}
      </main>
    </div>
  )
}
