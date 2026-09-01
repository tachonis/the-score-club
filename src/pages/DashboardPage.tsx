import { useEffect, useMemo, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { DashboardBadgesCard } from '../components/DashboardBadgesCard'
import { PushNotificationsCard } from '../components/PushNotificationsCard'
import { LoadingMark } from '../components/BrandAssets'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { dateLocale, t } from '../i18n'
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
        setLoadError(t('errors.identifyUser'))
        setLoading(false)
        return
      }

      const { data: leaderboardData, error: leaderboardError } =
        await supabase.rpc('get_leaderboard')

      if (leaderboardError) {
        setLoadError(
          t('errors.loadStandingsStats', { detail: leaderboardError.message }),
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
          t('errors.loadUpcomingMatches', { detail: matchdayError.message }),
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
          t('errors.loadPredictions', { detail: predictionsError.message }),
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
      return t('dashboard.nextMatches')
    }

    if (roundComplete || allFinished) {
      return t('dashboard.completedMatches')
    }

    if (isLeaguePhaseStage(nextMatchday.stage)) {
      return t('dashboard.nextMatchday')
    }

    return t('dashboard.nextMatches')
  }

  const formatDate = (dateValue: string) => {
    return new Intl.DateTimeFormat(dateLocale, {
      weekday: 'long',
      day: '2-digit',
      month: 'long',
      year: 'numeric',
    }).format(new Date(dateValue))
  }

  const formatTime = (dateValue: string) => {
    return new Intl.DateTimeFormat(dateLocale, {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(dateValue))
  }

  const matchdayStatusLabel = () => {
    if (!nextMatchday) {
      return t('dashboard.noMatches')
    }

    if (matches.length === 0) {
      return t('dashboard.notStarted')
    }

    if (allFinished) {
      return t('dashboard.finished')
    }

    if (allLocked) {
      return t('dashboard.locked')
    }

    const allScheduled = matches.every(
      (match) => match.status === 'scheduled',
    )

    if (allScheduled) {
      return t('dashboard.notStarted')
    }

    return t('dashboard.inProgress')
  }

  const roundDescription = () => {
    if (allFinished) {
      return t('dashboard.roundFinished')
    }

    if (allLocked) {
      return t('dashboard.predictionsLocked')
    }

    return t('dashboard.lockNote')
  }

  const ctaLabel =
    totalMatches > 0 && (allLocked || allFinished || savedPredictions === totalMatches)
      ? t('dashboard.checkPredictions')
      : t('dashboard.makePredictions')

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

            <h1>{t('dashboard.welcome', { username })}</h1>

            <p>{t('dashboard.intro')}</p>
          </div>
        </section>

        {loadError && (
          <p className="auth-message error">{loadError}</p>
        )}

        <section
          className="player-summary"
          aria-label={t('dashboard.playerSummary')}
        >
          <article className="summary-card">
            <span>{t('dashboard.position')}</span>
            <strong>
              {loading ? t('common.dash') : (playerStats?.rank_position ?? t('common.dash'))}
            </strong>
            <small>
              {playerStats
                ? t('dashboard.inOverall')
                : t('dashboard.noRankingYet')}
            </small>
          </article>

          <article className="summary-card">
            <span>{t('dashboard.totalPoints')}</span>
            <strong>{loading ? t('common.dash') : (playerStats?.total_points ?? 0)}</strong>
            <small>
              {playerStats
                ? t('dashboard.exactCorrect', {
                    exact: playerStats.exact_scores,
                    correct: playerStats.correct_results,
                  })
                : t('dashboard.scoringNotStarted')}
            </small>
          </article>

          <article className="summary-card">
            <span>{t('dashboard.predictions')}</span>

            <strong>
              {loading ? t('common.dash') : `${savedPredictions} / ${totalMatches}`}
            </strong>

            <small>
              {nextMatchday
                ? showRoundSubtitle
                  ? `${stageLabel} · ${roundLabel}`
                  : stageLabel
                : t('dashboard.noActiveRound')}
            </small>
          </article>
        </section>

        <DashboardBadgesCard />

        <PushNotificationsCard />

        {loading ? (
          <section className="dashboard-loading-card">
            <LoadingMark />
            <p>{t('dashboard.loadingMatches')}</p>
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
                  {t('dashboard.kickoffAt', {
                    date: formatDate(nextKickoff),
                    time: formatTime(nextKickoff),
                  })}
                </p>
              ) : (
                <p className="matchday-date">
                  {t('dashboard.noMatchesAdded')}
                </p>
              )}

              <p className="matchday-description">
                {roundDescription()}
              </p>

              <div className="prediction-progress">
                <div className="progress-labels">
                  <span>{t('dashboard.progress')}</span>

                  <strong>
                    {t('dashboard.progressCount', {
                      saved: savedPredictions,
                      total: totalMatches,
                    })}
                  </strong>
                </div>

                <div
                  className="progress-track"
                  role="progressbar"
                  aria-label={t('dashboard.progress')}
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
            <h2>{t('dashboard.emptyTitle')}</h2>

            <p>{t('dashboard.emptyBody')}</p>
          </section>
        )}
      </main>

    </div>
  )
}
