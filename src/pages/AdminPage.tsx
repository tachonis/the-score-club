import { useEffect, useMemo, useRef, useState } from 'react'
import { dateLocale, t } from '../i18n'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { AdminCupPanel } from '../components/cup/AdminCupPanel'
import { AdminFeedbackPanel } from '../components/AdminFeedbackPanel'
import { AdminNotificationsPanel } from '../components/AdminNotificationsPanel'
import { AdminResultConfirmModal } from '../components/AdminResultConfirmModal'
import { LongTermOutcomesPanel } from '../components/LongTermOutcomesPanel'
import {
  classifySetMatchResultError,
  isAllowedAdminScoreDraft,
  parseAdminScore,
  type PendingAdminResult,
} from '../lib/adminResult'
import {
  compareMatchdays,
  formatMatchdayLabel,
  isFinalStage,
  isLeaguePhaseStage,
} from '../lib/stages'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { supabase } from '../lib/supabase'

type AdminPageProps = {
  username: string
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type Team = {
  id: number
  name: string
  short_name: string | null
}

type Matchday = {
  id: number
  name: string
  matchday_number: number | null
  stage: string
}

type AdminMatch = {
  id: number
  matchday_id: number
  kickoff_at: string
  status: 'scheduled' | 'live' | 'finished' | 'postponed' | 'cancelled'
  home_score: number | null
  away_score: number | null
  matchday: Matchday
  home_team: Team
  away_team: Team
}

type ScoreDraft = {
  home: string
  away: string
}

type ResultResponse = {
  scored_predictions: number
  changed_predictions: number
}

const statusLabels: Record<AdminMatch['status'], string> = {
  scheduled: t('admin.scheduled'),
  live: t('admin.live'),
  finished: t('admin.finished'),
  postponed: t('admin.postponed'),
  cancelled: t('admin.cancelled'),
}

export function AdminPage({
  username,
  onNavigate,
  onLogout,
}: AdminPageProps) {
  const [matches, setMatches] = useState<AdminMatch[]>([])
  const [selectedMatchdayId, setSelectedMatchdayId] = useState<number | null>(
    null,
  )
  const [drafts, setDrafts] = useState<Record<number, ScoreDraft>>({})
  const [savingMatchId, setSavingMatchId] = useState<number | null>(null)
  const [correctingMatchId, setCorrectingMatchId] = useState<number | null>(
    null,
  )
  const [pendingResult, setPendingResult] =
    useState<PendingAdminResult | null>(null)
  const [outcomesRefreshKey, setOutcomesRefreshKey] = useState(0)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )
  const submitLockRef = useRef(false)

  const loadMatches = async (
    preferredMatchdayId?: number | null,
    options?: { quiet?: boolean },
  ) => {
    if (!options?.quiet) {
      setLoading(true)
    }

    const { data, error } = await supabase
      .from('matches')
      .select(`
        id,
        matchday_id,
        kickoff_at,
        status,
        home_score,
        away_score,
        matchday:matchdays (
          id,
          name,
          matchday_number,
          stage
        ),
        home_team:teams!matches_home_team_id_fkey (
          id,
          name,
          short_name
        ),
        away_team:teams!matches_away_team_id_fkey (
          id,
          name,
          short_name
        )
      `)
      .order('kickoff_at', { ascending: true })

    if (error) {
      setMessageType('error')
      setMessage(t('admin.loadFailed', { detail: error.message }))
      setLoading(false)
      return
    }

    const loadedMatches = (data ?? []) as unknown as AdminMatch[]
    const loadedDrafts: Record<number, ScoreDraft> = {}

    loadedMatches.forEach((match) => {
      loadedDrafts[match.id] = {
        home: match.home_score === null ? '' : String(match.home_score),
        away: match.away_score === null ? '' : String(match.away_score),
      }
    })

    setMatches(loadedMatches)
    setDrafts(loadedDrafts)

    const uniqueMatchdays = new Map<number, Matchday>()

    loadedMatches.forEach((match) => {
      uniqueMatchdays.set(match.matchday.id, match.matchday)
    })

    const orderedMatchdays = Array.from(uniqueMatchdays.values()).sort(
      compareMatchdays,
    )
    const matchdayIds = new Set(orderedMatchdays.map((matchday) => matchday.id))

    if (preferredMatchdayId && matchdayIds.has(preferredMatchdayId)) {
      setSelectedMatchdayId(preferredMatchdayId)
    } else {
      setSelectedMatchdayId(orderedMatchdays[0]?.id ?? null)
    }

    setLoading(false)
  }

  useEffect(() => {
    void loadMatches()
  }, [])

  useEffect(() => {
    setCorrectingMatchId(null)
    setPendingResult(null)
  }, [selectedMatchdayId])

  const matchdays = useMemo(() => {
    const uniqueMatchdays = new Map<number, Matchday>()

    matches.forEach((match) => {
      uniqueMatchdays.set(match.matchday.id, match.matchday)
    })

    return Array.from(uniqueMatchdays.values()).sort(compareMatchdays)
  }, [matches])

  const selectedMatches = useMemo(() => {
    return matches.filter(
      (match) => match.matchday_id === selectedMatchdayId,
    )
  }, [matches, selectedMatchdayId])

  const handleScoreChange = (
    matchId: number,
    side: keyof ScoreDraft,
    value: string,
  ) => {
    if (!isAllowedAdminScoreDraft(value)) return

    setDrafts((current) => ({
      ...current,
      [matchId]: {
        ...(current[matchId] ?? { home: '', away: '' }),
        [side]: value,
      },
    }))
  }

  const closePendingResult = () => {
    if (submitLockRef.current) {
      return
    }

    setPendingResult(null)
  }

  const beginCorrection = (match: AdminMatch) => {
    setMessage('')
    setCorrectingMatchId(match.id)
    setDrafts((current) => ({
      ...current,
      [match.id]: {
        home: match.home_score === null ? '' : String(match.home_score),
        away: match.away_score === null ? '' : String(match.away_score),
      },
    }))
  }

  const cancelCorrection = (match: AdminMatch) => {
    setCorrectingMatchId(null)
    setPendingResult(null)
    setDrafts((current) => ({
      ...current,
      [match.id]: {
        home: match.home_score === null ? '' : String(match.home_score),
        away: match.away_score === null ? '' : String(match.away_score),
      },
    }))
  }

  const handleSaveResult = (match: AdminMatch) => {
    if (submitLockRef.current || savingMatchId !== null) {
      return
    }

    if (match.status === 'finished' && correctingMatchId !== match.id) {
      beginCorrection(match)
      return
    }

    const draft = drafts[match.id] ?? { home: '', away: '' }
    const homeScore = parseAdminScore(draft.home)
    const awayScore = parseAdminScore(draft.away)

    if (!homeScore.ok) {
      setMessageType('error')
      setMessage(homeScore.message)
      return
    }

    if (!awayScore.ok) {
      setMessageType('error')
      setMessage(awayScore.message)
      return
    }

    if (
      match.status === 'finished' &&
      homeScore.value === match.home_score &&
      awayScore.value === match.away_score
    ) {
      setMessageType('error')
      setMessage(t('admin.noChange'))
      return
    }

    setMessage('')
    setPendingResult({
      matchId: match.id,
      homeName: match.home_team.name,
      awayName: match.away_team.name,
      homeScore: homeScore.value,
      awayScore: awayScore.value,
      storedHomeScore: match.home_score,
      storedAwayScore: match.away_score,
      kind: match.status === 'finished' ? 'correction' : 'entry',
    })
  }

  const submitPendingResult = async () => {
    if (!pendingResult || submitLockRef.current || savingMatchId !== null) {
      return
    }

    submitLockRef.current = true
    setSavingMatchId(pendingResult.matchId)
    setMessage('')

    const { data, error } = await supabase.rpc('set_match_result', {
      p_match_id: pendingResult.matchId,
      p_home_score: pendingResult.homeScore,
      p_away_score: pendingResult.awayScore,
    })

    if (error) {
      setMessageType('error')
      setMessage(classifySetMatchResultError(error))
      submitLockRef.current = false
      setSavingMatchId(null)
      return
    }

    const result = (data?.[0] ?? null) as ResultResponse | null

    setMessageType('success')
    setMessage(
      t('admin.saved', {
        home: pendingResult.homeName,
        away: pendingResult.awayName,
        scored: result?.scored_predictions ?? 0,
        changed: result?.changed_predictions ?? 0,
      }),
    )

    setPendingResult(null)
    setCorrectingMatchId(null)
    await loadMatches(selectedMatchdayId, { quiet: true })
    setOutcomesRefreshKey((current) => current + 1)
    submitLockRef.current = false
    setSavingMatchId(null)
  }

  const selectedMatchday = matchdays.find(
    (matchday) => matchday.id === selectedMatchdayId,
  )
  const selectedStage = selectedMatchday?.stage ?? null
  const showKnockoutScoringNote =
    selectedStage !== null && !isLeaguePhaseStage(selectedStage)
  const showFinalScoringNote =
    selectedStage !== null && isFinalStage(selectedStage)

  const formatKickoff = (dateValue: string) => {
    return new Intl.DateTimeFormat(dateLocale, {
      weekday: 'short',
      day: '2-digit',
      month: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(dateValue))
  }

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="admin"
        username={username}
        role="admin"
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="admin-main">
        <section className="admin-heading">
          <div>
            <p className="dashboard-eyebrow">
              {formatGreekAllCaps(t('admin.kicker'))}
            </p>
            <h1>{t('admin.heading')}</h1>
            <p>
              {t('admin.intro')}
            </p>
          </div>

          {matchdays.length > 0 && (
            <label className="admin-matchday-select">
              <span>{formatGreekAllCaps(t('admin.stage'))}</span>
              <select
                value={selectedMatchdayId ?? ''}
                disabled={savingMatchId !== null || pendingResult !== null}
                onChange={(event) =>
                  setSelectedMatchdayId(Number(event.target.value))
                }
              >
                {matchdays.map((matchday) => (
                  <option key={matchday.id} value={matchday.id}>
                    {formatMatchdayLabel(
                      matchday.stage,
                      matchday.matchday_number,
                      matchday.name,
                    )}
                  </option>
                ))}
              </select>
            </label>
          )}
        </section>

        {message && (
          <p
            className={`auth-message ${
              messageType === 'error' ? 'error' : 'success'
            }`}
          >
            {message}
          </p>
        )}

        <AdminCupPanel refreshKey={outcomesRefreshKey} />

        <AdminNotificationsPanel />

        <AdminFeedbackPanel />

        <LongTermOutcomesPanel refreshKey={outcomesRefreshKey} />

        {loading ? (
          <section className="app-loading-inline">
            <LoadingMark />
            <p>{t('admin.loading')}</p>
          </section>
        ) : selectedMatches.length === 0 ? (
          <section className="empty-state">
            <h2>{t('admin.emptyTitle')}</h2>
            <p>{t('admin.emptyBody')}</p>
          </section>
        ) : (
          <section className="admin-matches-list">
            <div className="admin-scoring-notes">
              <p>{t('admin.score90')}</p>
              {showKnockoutScoringNote && (
                <p>
                  {t('admin.knockoutNoEt')}
                </p>
              )}
              {showFinalScoringNote && (
                <p className="admin-final-note">
                  {t('admin.finalNote')}
                </p>
              )}
            </div>

            {selectedMatches.map((match) => {
              const draft = drafts[match.id] ?? { home: '', away: '' }
              const isSaving = savingMatchId === match.id
              const isFinished = match.status === 'finished'
              const isCorrecting = correctingMatchId === match.id
              const scoresLocked = isFinished && !isCorrecting
              const actionsBusy = savingMatchId !== null || pendingResult !== null

              return (
                <article
                  className={`admin-match-card${isCorrecting ? ' correcting' : ''}`}
                  key={match.id}
                >
                  <div className="admin-match-meta">
                    <span>{formatKickoff(match.kickoff_at)}</span>
                    <span className={`admin-status ${match.status}`}>
                      {statusLabels[match.status]}
                    </span>
                  </div>

                  <div className="admin-result-row">
                    <strong>{match.home_team.name}</strong>
                    <div className="admin-score-inputs">
                      <input
                        type="text"
                        inputMode="numeric"
                        maxLength={2}
                        value={draft.home}
                        disabled={scoresLocked || isSaving}
                        onChange={(event) =>
                          handleScoreChange(match.id, 'home', event.target.value)
                        }
                        aria-label={t('admin.scoreAria', {
                          team: match.home_team.name,
                        })}
                      />
                      <span>:</span>
                      <input
                        type="text"
                        inputMode="numeric"
                        maxLength={2}
                        value={draft.away}
                        disabled={scoresLocked || isSaving}
                        onChange={(event) =>
                          handleScoreChange(match.id, 'away', event.target.value)
                        }
                        aria-label={t('admin.scoreAria', {
                          team: match.away_team.name,
                        })}
                      />
                    </div>
                    <strong>{match.away_team.name}</strong>
                  </div>

                  <div className="admin-match-actions">
                    <button
                      type="button"
                      className="admin-save-button"
                      disabled={actionsBusy}
                      onClick={() => handleSaveResult(match)}
                    >
                      {isSaving
                        ? t('common.saving')
                        : scoresLocked
                          ? t('admin.correctResult')
                          : isFinished
                            ? t('admin.confirmCorrection')
                            : t('admin.saveResult')}
                    </button>
                    {isCorrecting ? (
                      <button
                        type="button"
                        className="admin-notifications-cancel"
                        disabled={actionsBusy}
                        onClick={() => cancelCorrection(match)}
                      >
                        {t('admin.cancelCorrection')}
                      </button>
                    ) : null}
                  </div>
                </article>
              )
            })}
          </section>
        )}
      </main>

      {pendingResult ? (
        <AdminResultConfirmModal
          pending={pendingResult}
          saving={savingMatchId === pendingResult.matchId}
          errorText={messageType === 'error' ? message : ''}
          onCancel={closePendingResult}
          onConfirm={() => void submitPendingResult()}
        />
      ) : null}

    </div>
  )
}
