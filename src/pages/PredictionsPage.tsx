import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { LongTermPredictionsSection } from '../components/LongTermPredictionsSection'
import { ScoreStepper } from '../components/ScoreStepper'
import {
  compareMatchdays,
  formatMatchdayLabel,
  formatMatchdayTabLabel,
  getMatchdayHeadingEyebrow,
  getMatchdayRoundLabel,
  isFinalStage,
  isGoldenMatchAvailable,
  isGoldenMatchStage,
  isKnockoutPredictionStage,
} from '../lib/stages'
import {
  buildPredictionSaveFeedback,
  classifyPredictionSaveError,
} from '../lib/predictionSave'
import { supabase } from '../lib/supabase'
import { getCompactTeamName } from '../lib/teamDisplayName'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { dateLocale, selectPlural, t } from '../i18n'

type PredictionsPageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type Team = {
  id: number
  name: string
  short_name: string | null
  logo_url: string | null
}

type Matchday = {
  id: number
  name: string
  stage: string
  matchday_number: number | null
}

type Match = {
  id: number
  matchday_id: number
  kickoff_at: string
  status:
    | 'scheduled'
    | 'live'
    | 'finished'
    | 'postponed'
    | 'cancelled'
  home_score: number | null
  away_score: number | null
  matchday: Matchday
  home_team: Team
  away_team: Team
}

type PredictionValues = {
  home: string
  away: string
}

type StoredPrediction = {
  id: number
  match_id: number
  predicted_home_score: number
  predicted_away_score: number
  points: number | null
}

type GoldenMatchSelection = {
  match_id: number
  matchday_id: number
}

const uniqueOrderedMatchdays = (matches: Match[]) => {
  const uniqueMatchdays = new Map<number, Matchday>()

  matches.forEach((match) => {
    uniqueMatchdays.set(match.matchday.id, match.matchday)
  })

  return Array.from(uniqueMatchdays.values()).sort(compareMatchdays)
}

const isMatchOpenForPredictions = (match: Match, now: number) => {
  return (
    match.status === 'scheduled' &&
    now < new Date(match.kickoff_at).getTime()
  )
}

const selectPreferredMatchdayId = (
  orderedMatchdays: Matchday[],
  matches: Match[],
  now: number,
) => {
  const matchdaysWithMatches = orderedMatchdays.filter((matchday) =>
    matches.some((match) => match.matchday_id === matchday.id),
  )
  const candidates =
    matchdaysWithMatches.length > 0 ? matchdaysWithMatches : orderedMatchdays

  if (candidates.length === 0) {
    return null
  }

  const matchesFor = (matchdayId: number) =>
    matches.filter((match) => match.matchday_id === matchdayId)

  const isComplete = (matchday: Matchday) => {
    const roundMatches = matchesFor(matchday.id)

    return (
      roundMatches.length > 0 &&
      roundMatches.every((match) => match.status === 'finished')
    )
  }

  const hasOpenMatch = (matchday: Matchday) =>
    matchesFor(matchday.id).some((match) =>
      isMatchOpenForPredictions(match, now),
    )

  const incomplete = candidates.filter((matchday) => !isComplete(matchday))
  const withOpenPredictions = incomplete.find(hasOpenMatch)

  if (withOpenPredictions) {
    return withOpenPredictions.id
  }

  if (incomplete.length > 0) {
    return incomplete[0].id
  }

  return candidates[candidates.length - 1].id
}

export function PredictionsPage({
  username,
  role,
  onNavigate,
  onLogout,
}: PredictionsPageProps) {
  const [matches, setMatches] = useState<Match[]>([])

  const [selectedMatchdayId, setSelectedMatchdayId] = useState<
    number | null
  >(null)

  const [predictions, setPredictions] = useState<
    Record<number, PredictionValues>
  >({})

  const [savedPredictions, setSavedPredictions] = useState<
    Record<number, PredictionValues>
  >({})

  const [predictionPoints, setPredictionPoints] = useState<
    Record<number, number | null>
  >({})

  const [goldenMatches, setGoldenMatches] = useState<
    Record<number, number>
  >({})

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [savingGoldenMatchId, setSavingGoldenMatchId] = useState<
    number | null
  >(null)
  const [now, setNow] = useState(() => Date.now())
  const [locallyLockedMatchIds, setLocallyLockedMatchIds] = useState<
    ReadonlySet<number>
  >(() => new Set())
  const [message, setMessage] = useState('')

  const [messageType, setMessageType] = useState<
    'success' | 'error'
  >('success')
  const [recentSaveFlash, setRecentSaveFlash] = useState(false)
  const saveFlashTimeoutRef = useRef<number | null>(null)
  const awayInputRefs = useRef<Record<number, HTMLInputElement | null>>({})
  const matchdayTabRefs = useRef<Record<number, HTMLButtonElement | null>>({})
  const userPickedMatchdayRef = useRef(false)

  useEffect(() => {
    return () => {
      if (saveFlashTimeoutRef.current !== null) {
        window.clearTimeout(saveFlashTimeoutRef.current)
      }
    }
  }, [])

  useEffect(() => {
    const loadPageData = async () => {
      setLoading(true)
      setMessage('')

      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser()

      if (userError || !user) {
        setMessageType('error')
        setMessage(t('errors.identifyUser'))
        setLoading(false)
        return
      }

      const { data: matchesData, error: matchesError } =
        await supabase
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
              stage,
              matchday_number
            ),
            home_team:teams!matches_home_team_id_fkey (
              id,
              name,
              short_name,
              logo_url
            ),
            away_team:teams!matches_away_team_id_fkey (
              id,
              name,
              short_name,
              logo_url
            )
          `)
          .order('kickoff_at', { ascending: true })

      if (matchesError) {
        setMessageType('error')
        setMessage(
          t('errors.loadMatches', { detail: matchesError.message }),
        )
        setLoading(false)
        return
      }

      const loadedMatches =
        (matchesData ?? []) as unknown as Match[]

      const [predictionsResult, goldenMatchesResult] =
        await Promise.all([
          supabase
            .from('predictions')
            .select(`
              id,
              match_id,
              predicted_home_score,
              predicted_away_score,
              points
            `)
            .eq('user_id', user.id),
          supabase
            .from('golden_match_selections')
            .select('match_id, matchday_id')
            .eq('user_id', user.id),
        ])

      const {
        data: predictionsData,
        error: predictionsError,
      } = predictionsResult

      if (predictionsError) {
        setMessageType('error')
        setMessage(
          t('errors.loadPredictions', { detail: predictionsError.message }),
        )
        setLoading(false)
        return
      }

      if (goldenMatchesResult.error) {
        setMessageType('error')
        setMessage(
          t('errors.loadGoldenMatches', { detail: goldenMatchesResult.error.message }),
        )
        setLoading(false)
        return
      }

      const loadedPredictions =
        (predictionsData ?? []) as StoredPrediction[]

      const predictionValues: Record<number, PredictionValues> = {}
      const loadedPoints: Record<number, number | null> = {}

      loadedPredictions.forEach((prediction) => {
        predictionValues[prediction.match_id] = {
          home: String(prediction.predicted_home_score),
          away: String(prediction.predicted_away_score),
        }
        loadedPoints[prediction.match_id] = prediction.points
      })

      const loadedGoldenMatches =
        (goldenMatchesResult.data ?? []) as GoldenMatchSelection[]
      const goldenMatchValues: Record<number, number> = {}

      loadedGoldenMatches.forEach((selection) => {
        goldenMatchValues[selection.matchday_id] = selection.match_id
      })

      setMatches(loadedMatches)
      setPredictions(predictionValues)
      setSavedPredictions(predictionValues)
      setPredictionPoints(loadedPoints)
      setGoldenMatches(goldenMatchValues)

      if (!userPickedMatchdayRef.current) {
        setSelectedMatchdayId(
          selectPreferredMatchdayId(
            uniqueOrderedMatchdays(loadedMatches),
            loadedMatches,
            Date.now(),
          ),
        )
      }

      setLoading(false)
    }

    void loadPageData()
  }, [])

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 30_000)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    if (selectedMatchdayId === null) {
      return
    }

    matchdayTabRefs.current[selectedMatchdayId]?.scrollIntoView({
      block: 'nearest',
      inline: 'nearest',
    })
  }, [selectedMatchdayId])

  const matchdays = useMemo(
    () => uniqueOrderedMatchdays(matches),
    [matches],
  )

  const selectedMatches = useMemo(() => {
    if (selectedMatchdayId === null) {
      return []
    }

    return matches.filter(
      (match) => match.matchday_id === selectedMatchdayId,
    )
  }, [matches, selectedMatchdayId])

  const selectedMatchday = matchdays.find(
    (matchday) => matchday.id === selectedMatchdayId,
  )

  const selectedStage = selectedMatchday?.stage ?? ''
  const showGoldenMatchGuide = isGoldenMatchStage(selectedStage)
  const goldenMatchIsAvailable = isGoldenMatchAvailable(
    selectedStage,
    selectedMatchday?.matchday_number ?? null,
  )
  const showKnockoutScoringNote = isKnockoutPredictionStage(selectedStage)
  const showFinalScoringNote = isFinalStage(selectedStage)
  const selectedGoldenMatchId = selectedMatchdayId === null
    ? null
    : (goldenMatches[selectedMatchdayId] ?? null)

  const isMatchLockedAt = (match: Match, at: number) => {
    return (
      locallyLockedMatchIds.has(match.id) ||
      match.status !== 'scheduled' ||
      at >= new Date(match.kickoff_at).getTime()
    )
  }

  const isMatchLocked = (match: Match) => {
    return isMatchLockedAt(match, now)
  }

  const selectedGoldenMatch = selectedMatches.find(
    (match) => match.id === selectedGoldenMatchId,
  )
  const goldenMatchIsLocked = selectedGoldenMatch
    ? isMatchLocked(selectedGoldenMatch)
    : false

  const hasCompletePrediction = (matchId: number) => {
    const prediction = predictions[matchId]

    return (
      prediction?.home !== undefined &&
      prediction.home !== '' &&
      prediction?.away !== undefined &&
      prediction.away !== ''
    )
  }

  const hasSavedPrediction = (matchId: number) => {
    const prediction = savedPredictions[matchId]

    return (
      prediction?.home !== undefined &&
      prediction.home !== '' &&
      prediction?.away !== undefined &&
      prediction.away !== ''
    )
  }

  const hasUnsavedChanges = (matchId: number) => {
    const current = predictions[matchId]
    const saved = savedPredictions[matchId]

    const currentHome = current?.home ?? ''
    const currentAway = current?.away ?? ''
    const savedHome = saved?.home ?? ''
    const savedAway = saved?.away ?? ''

    return currentHome !== savedHome || currentAway !== savedAway
  }

  const goldenMatchMissingSavedPrediction =
    goldenMatchIsAvailable &&
    selectedGoldenMatchId !== null &&
    !hasSavedPrediction(selectedGoldenMatchId)

  const handleScoreChange = (
    matchId: number,
    team: 'home' | 'away',
    value: string,
    options?: { skipAutoAdvance?: boolean },
  ) => {
    if (value !== '' && !/^\d{1,2}$/.test(value)) {
      return
    }

    if (value !== '' && Number(value) > 20) {
      return
    }

    setMessage('')

    setPredictions((currentPredictions) => ({
      ...currentPredictions,
      [matchId]: {
        home: currentPredictions[matchId]?.home ?? '',
        away: currentPredictions[matchId]?.away ?? '',
        [team]: value,
      },
    }))

    if (
      !options?.skipAutoAdvance &&
      team === 'home' &&
      value.length === 1
    ) {
      awayInputRefs.current[matchId]?.focus()
    }
  }

  const handleGoldenMatchSelection = async (match: Match) => {
    if (!goldenMatchIsAvailable) {
      setMessageType('error')
      setMessage(
        isGoldenMatchStage(selectedStage)
          ? t('golden.fromMd2')
          : t('golden.leaguePhaseOnly'),
      )
      return
    }

    if (isMatchLocked(match)) {
      setMessageType('error')
      setMessage(t('golden.matchAlreadyLocked'))
      return
    }

    if (goldenMatchIsLocked) {
      setMessageType('error')
      setMessage(
        t('golden.lockedAfterKickoff'),
      )
      return
    }

    setSavingGoldenMatchId(match.id)
    setMessage('')

    const { data, error } = await supabase.rpc('set_golden_match', {
      p_match_id: match.id,
    })

    if (error) {
      const knownMessages: Record<string, string> = {
        'Golden Match is available from Matchday 2': t('golden.fromMd2'),
        'Golden Match is available only during the League Phase':
          t('golden.leaguePhaseOnly'),
        'Golden Match must be selected before kickoff': t('golden.beforeKickoff'),
        'Golden Match is locked after its kickoff': t('golden.lockedCannotChange'),
      }

      setMessageType('error')
      setMessage(
        knownMessages[error.message] ??
          t('golden.saveFailedDetail', { detail: error.message }),
      )
      setSavingGoldenMatchId(null)
      return
    }

    const selection = Array.isArray(data) ? data[0] : data
    const matchdayId = selection?.matchday_id ?? match.matchday_id

    setGoldenMatches((current) => ({
      ...current,
      [matchdayId]: match.id,
    }))
    setMessageType('success')
    setMessage(
      selectedGoldenMatchId === null
        ? t('golden.savedOk')
        : t('golden.replacedOk'),
    )
    setSavingGoldenMatchId(null)
  }

  const completedPredictions = selectedMatches.filter((match) =>
    hasCompletePrediction(match.id),
  ).length

  const savedPredictionCount = selectedMatches.filter((match) =>
    hasSavedPrediction(match.id),
  ).length

  const unsavedChangesCount = selectedMatches.filter((match) =>
    hasUnsavedChanges(match.id),
  ).length

  const handleSavePredictions = async () => {
    setSaving(true)
    setMessage('')

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser()

    if (userError || !user) {
      setMessageType('error')
      setMessage(t('errors.identifyUser'))
      setSaving(false)
      return
    }

    const saveNow = Date.now()
    setNow(saveNow)

    const dirtyCompleteMatches = selectedMatches.filter(
      (match) =>
        hasCompletePrediction(match.id) && hasUnsavedChanges(match.id),
    )

    if (dirtyCompleteMatches.length === 0) {
      setMessageType('error')

      if (completedPredictions === 0) {
        setMessage(
          t('predictions.fillOne'),
        )
      } else {
        setMessage(t('predictions.noChanges'))
      }

      setSaving(false)
      return
    }

    const alreadyLockedMatches = dirtyCompleteMatches.filter((match) =>
      isMatchLockedAt(match, saveNow),
    )
    const matchesToSave = dirtyCompleteMatches.filter(
      (match) => !isMatchLockedAt(match, saveNow),
    )

    const lockMatch = (match: Match) => ({
      homeName: match.home_team.name,
      awayName: match.away_team.name,
    })

    const revertLockedDrafts = (lockedMatches: Match[]) => {
      if (lockedMatches.length === 0) {
        return
      }

      setPredictions((currentPredictions) => {
        const nextPredictions = { ...currentPredictions }

        lockedMatches.forEach((match) => {
          const saved = savedPredictions[match.id]

          nextPredictions[match.id] = saved
            ? { home: saved.home, away: saved.away }
            : { home: '', away: '' }
        })

        return nextPredictions
      })
    }

    const markMatchesLocallyLocked = (lockedMatches: Match[]) => {
      if (lockedMatches.length === 0) {
        return
      }

      setLocallyLockedMatchIds((current) => {
        const next = new Set(current)

        lockedMatches.forEach((match) => {
          next.add(match.id)
        })

        return next
      })
    }

    if (matchesToSave.length === 0) {
      revertLockedDrafts(alreadyLockedMatches)
      markMatchesLocallyLocked(alreadyLockedMatches)
      setMessageType('error')
      setMessage(
        buildPredictionSaveFeedback({
          savedCount: 0,
          lockedLabels: alreadyLockedMatches.map(lockMatch),
          genericFailureCount: 0,
        }).text,
      )
      setSaving(false)
      return
    }

    const settledResults = await Promise.allSettled(
      matchesToSave.map(async (match) => {
        const payload = {
          user_id: user.id,
          match_id: match.id,
          predicted_home_score: Number(predictions[match.id].home),
          predicted_away_score: Number(predictions[match.id].away),
          updated_at: new Date().toISOString(),
        }

        const { error } = await supabase.from('predictions').upsert(payload, {
          onConflict: 'user_id,match_id',
        })

        return { match, payload, error }
      }),
    )

    setNow(Date.now())

    const succeeded: Array<{
      match: Match
      payload: {
        match_id: number
        predicted_home_score: number
        predicted_away_score: number
      }
    }> = []
    const raceLockedMatches: Match[] = []
    let genericFailureCount = 0

    settledResults.forEach((result) => {
      if (result.status === 'rejected') {
        genericFailureCount += 1
        return
      }

      if (result.value.error) {
        const looksLocked =
          classifyPredictionSaveError(result.value.error) === 'locked'
        const matchLockedNow = isMatchLockedAt(
          result.value.match,
          Date.now(),
        )

        // Disabled-account RLS looks like any other policy denial. Only treat
        // it as a kickoff lock when this match is actually locked client-side.
        if (looksLocked && matchLockedNow) {
          raceLockedMatches.push(result.value.match)
        } else {
          genericFailureCount += 1
        }
        return
      }

      succeeded.push(result.value)
    })

    const lockedMatches = [...alreadyLockedMatches, ...raceLockedMatches]

    if (succeeded.length > 0) {
      const updatedSavedPredictions = {
        ...savedPredictions,
      }

      succeeded.forEach(({ payload }) => {
        updatedSavedPredictions[payload.match_id] = {
          home: String(payload.predicted_home_score),
          away: String(payload.predicted_away_score),
        }
      })

      setSavedPredictions(updatedSavedPredictions)
    }

    revertLockedDrafts(lockedMatches)
    markMatchesLocallyLocked(lockedMatches)

    const feedback = buildPredictionSaveFeedback({
      savedCount: succeeded.length,
      lockedLabels: lockedMatches.map(lockMatch),
      genericFailureCount,
    })

    setMessageType(feedback.tone)
    setMessage(feedback.text)

    if (feedback.tone === 'success') {
      setRecentSaveFlash(true)
      if (saveFlashTimeoutRef.current !== null) {
        window.clearTimeout(saveFlashTimeoutRef.current)
      }
      saveFlashTimeoutRef.current = window.setTimeout(() => {
        setRecentSaveFlash(false)
        setMessage('')
        saveFlashTimeoutRef.current = null
      }, 2600)
    }

    setSaving(false)
  }

  const hasPendingSave = unsavedChangesCount > 0 || saving

  const formatMatchDate = (kickoffAt: string) => {
    return new Intl.DateTimeFormat(dateLocale, {
      weekday: 'short',
      day: '2-digit',
      month: 'long',
    }).format(new Date(kickoffAt))
  }

  const formatMatchTime = (kickoffAt: string) => {
    return new Intl.DateTimeFormat(dateLocale, {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(kickoffAt))
  }

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="predictions"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main
        className={[
          'predictions-main',
          hasPendingSave || recentSaveFlash
            ? 'predictions-main--floating-save'
            : '',
        ]
          .filter(Boolean)
          .join(' ')}
      >
        <section className="predictions-heading">
          <div>
            <p className="dashboard-eyebrow">
              Champions League 2026/27
            </p>

            <h1>{t('predictions.title')}</h1>

            <p>{t('predictions.intro')}</p>
          </div>

          <div className="predictions-counter">
            <span>{t('predictions.savedCount')}</span>

            <strong>
              {savedPredictionCount} / {selectedMatches.length}
            </strong>
          </div>
        </section>

        <LongTermPredictionsSection />

        {loading ? (
          <section className="app-loading-inline">
            <LoadingMark />
            <p>{t('predictions.loading')}</p>
          </section>
        ) : matches.length === 0 ? (
          <section className="empty-state">
            <h2>{t('predictions.emptyTitle')}</h2>

            <p>{t('predictions.emptyBody')}</p>
          </section>
        ) : (
          <>
            <section className="matchday-selector">
              <div className="matchday-tabs" role="tablist">
                {matchdays.map((matchday) => {
                  const isSelected = selectedMatchdayId === matchday.id

                  return (
                    <button
                      key={matchday.id}
                      ref={(element) => {
                        matchdayTabRefs.current[matchday.id] = element
                      }}
                      type="button"
                      role="tab"
                      aria-selected={isSelected}
                      aria-label={formatMatchdayLabel(
                        matchday.stage,
                        matchday.matchday_number,
                        matchday.name,
                      )}
                      className={`matchday-tab ${isSelected ? 'active' : ''}`}
                      onClick={() => {
                        userPickedMatchdayRef.current = true
                        setSelectedMatchdayId(matchday.id)
                      }}
                    >
                      {formatMatchdayTabLabel(
                        matchday.stage,
                        matchday.matchday_number,
                        matchday.name,
                      )}
                    </button>
                  )
                })}
              </div>
            </section>

            <section className="selected-matchday-info">
              <div>
                <span>
                  {formatGreekAllCaps(
                    getMatchdayHeadingEyebrow(selectedStage),
                  )}
                </span>

                <h2>
                  {selectedMatchday
                    ? getMatchdayRoundLabel(
                        selectedMatchday.stage,
                        selectedMatchday.matchday_number,
                        selectedMatchday.name,
                      )
                    : t('predictions.selectedStage')}
                </h2>
              </div>

              <div className="selected-matchday-notes">
                <p className="matchday-timezone-note">
                  {t('predictions.localTime')}
                </p>
                {showKnockoutScoringNote && (
                  <>
                    <p className="prediction-knockout-note">
                      {t('predictions.knockout90')}
                    </p>
                    <p className="prediction-knockout-note">
                      {t('predictions.noExtraTime')}
                    </p>
                  </>
                )}
                {showFinalScoringNote && (
                  <p className="prediction-final-note">
                    {t('predictions.finalScoring')}
                  </p>
                )}
              </div>
            </section>

            {showGoldenMatchGuide && (
            <section
              className={`golden-match-guide ${
                goldenMatchIsAvailable ? '' : 'inactive'
              } ${goldenMatchIsLocked ? 'locked' : ''}`}
            >
              <div className="golden-match-guide-icon" aria-hidden="true">
                ★
              </div>

              <div className="golden-match-guide-copy">
                <span>{t('golden.kicker')}</span>
                <h3>
                  {goldenMatchIsAvailable
                    ? t('golden.pickMatch')
                    : t('golden.fromMatchday2')}
                </h3>
                <p>
                  {goldenMatchIsAvailable
                    ? t('golden.availableHelp')
                    : t('golden.md1Help')}
                </p>
              </div>

              {goldenMatchIsAvailable && (
                <div className="golden-match-current">
                  <span>
                    {goldenMatchIsLocked
                      ? t('golden.locked')
                      : t('golden.currentPick')}
                  </span>
                  <strong>
                    {selectedGoldenMatch
                      ? `${selectedGoldenMatch.home_team.name} – ${selectedGoldenMatch.away_team.name}`
                      : t('golden.noneSelected')}
                  </strong>
                </div>
              )}

              {goldenMatchMissingSavedPrediction && selectedGoldenMatch && (
                <p
                  className="golden-match-prediction-warning"
                  role="status"
                >
                  {t('golden.missingScore')}
                </p>
              )}
            </section>
            )}

            <section className="matches-list">
              {selectedMatches.length === 0 ? (
                <div className="empty-state">
                  <h2>{t('predictions.emptyTitle')}</h2>
                  <p>{t('predictions.emptyStageBody')}</p>
                </div>
              ) : selectedMatches.map((match) => {
                const prediction = predictions[match.id] ?? {
                  home: '',
                  away: '',
                }

                const locked = isMatchLocked(match)
                const complete = hasCompletePrediction(match.id)
                const saved = hasSavedPrediction(match.id)
                const changed = hasUnsavedChanges(match.id)
                const goldenSelected = selectedGoldenMatchId === match.id
                const matchLocked = locked
                const points = predictionPoints[match.id]
                const isFinished = match.status === 'finished'
                const officialScore =
                  match.home_score !== null && match.away_score !== null
                    ? `${match.home_score}–${match.away_score}`
                    : null
                const savedScore = saved
                  ? `${savedPredictions[match.id].home}–${savedPredictions[match.id].away}`
                  : null

                return (
                  <article
                    key={match.id}
                    className={`prediction-match-card ${
                      saved && !changed ? 'completed' : ''
                    } ${changed ? 'unsaved' : ''} ${
                      locked ? 'locked' : ''
                    } ${goldenSelected ? 'golden-selected' : ''}`}
                  >
                    <div className="match-meta">
                      <span>
                        {formatMatchDate(match.kickoff_at)}
                      </span>

                      <strong>
                        {formatMatchTime(match.kickoff_at)}
                      </strong>

                      {/* Compact Golden Match indicator — mobile only */}
                      {goldenMatchIsAvailable && (
                        goldenSelected ? (
                          <span
                            className={`match-meta-golden-badge ${matchLocked ? 'locked' : ''}`}
                            aria-label={matchLocked ? t('golden.selectedLocked') : t('golden.selected')}
                          >
                            ★
                          </span>
                        ) : !matchLocked && !goldenMatchIsLocked ? (
                          <button
                            type="button"
                            className="match-meta-golden-button"
                            disabled={savingGoldenMatchId !== null}
                            onClick={() => void handleGoldenMatchSelection(match)}
                            aria-label={t(
                              selectedGoldenMatchId === null
                                ? 'golden.selectAria'
                                : 'golden.replaceAria',
                              {
                                home: match.home_team.name,
                                away: match.away_team.name,
                              },
                            )}
                          >
                            {savingGoldenMatchId === match.id ? '…' : '☆'}
                          </button>
                        ) : null
                      )}
                    </div>

                    {(goldenSelected || (goldenMatchIsAvailable && !matchLocked && !goldenMatchIsLocked)) && (
                      <div className="golden-match-control">
                        {goldenSelected ? (
                          <span
                            className={`golden-match-selected-badge ${
                              matchLocked ? 'locked' : ''
                            }`}
                          >
                            <span aria-hidden="true">★</span>
                            {matchLocked
                              ? t('golden.selectedLocked')
                              : t('golden.selected')}
                          </span>
                        ) : (
                          <button
                            type="button"
                            className="golden-match-button"
                            disabled={savingGoldenMatchId !== null}
                            onClick={() =>
                              void handleGoldenMatchSelection(match)
                            }
                            aria-label={t(
                              selectedGoldenMatchId === null
                                ? 'golden.selectAria'
                                : 'golden.replaceAria',
                              {
                                home: match.home_team.name,
                                away: match.away_team.name,
                              },
                            )}
                          >
                            <span aria-hidden="true">☆</span>
                            {savingGoldenMatchId === match.id
                              ? t('common.saving')
                              : selectedGoldenMatchId === null
                                ? t('golden.select')
                                : t('golden.replace')}
                          </button>
                        )}
                      </div>
                    )}

                    {goldenSelected && !saved && (
                      <p
                        className="golden-match-prediction-warning golden-match-prediction-warning--card"
                        role="status"
                      >
                        {t('golden.missingScoreShort')}
                      </p>
                    )}

                    <div className="prediction-teams">
                      <div className="prediction-team home-team">
                        <span className="temporary-team-logo">
                          {match.home_team.short_name ??
                            match.home_team.name.charAt(0)}
                        </span>

                        <strong>
                          <span className="team-name-full">{match.home_team.name}</span>
                          <span className="team-name-short">
                            {getCompactTeamName(match.home_team.name, match.home_team.short_name)}
                          </span>
                        </strong>
                      </div>

                      <div className="score-prediction-inputs">
                        <ScoreStepper
                          value={prediction.home}
                          disabled={locked}
                          inputLabel={t('predictions.goals', { team: match.home_team.name })}
                          incrementLabel={t('predictions.increaseGoals', { team: match.home_team.name })}
                          decrementLabel={t('predictions.decreaseGoals', { team: match.home_team.name })}
                          onChange={(next, source) =>
                            handleScoreChange(match.id, 'home', next, {
                              skipAutoAdvance: source === 'stepper',
                            })
                          }
                        />

                        <span>:</span>

                        <ScoreStepper
                          value={prediction.away}
                          disabled={locked}
                          inputRef={(el) => {
                            awayInputRefs.current[match.id] = el
                          }}
                          inputLabel={t('predictions.goals', { team: match.away_team.name })}
                          incrementLabel={t('predictions.increaseGoals', { team: match.away_team.name })}
                          decrementLabel={t('predictions.decreaseGoals', { team: match.away_team.name })}
                          onChange={(next, source) =>
                            handleScoreChange(match.id, 'away', next, {
                              skipAutoAdvance: source === 'stepper',
                            })
                          }
                        />
                      </div>

                      <div className="prediction-team away-team">
                        <strong>
                          <span className="team-name-full">{match.away_team.name}</span>
                          <span className="team-name-short">
                            {getCompactTeamName(match.away_team.name, match.away_team.short_name)}
                          </span>
                        </strong>

                        <span className="temporary-team-logo">
                          {match.away_team.short_name ??
                            match.away_team.name.charAt(0)}
                        </span>
                      </div>
                    </div>

                    <div className="prediction-status">
                      {isFinished ? (
                        <div className="prediction-result-summary">
                          {officialScore && (
                            <p>{t('predictions.officialScore', { score: officialScore })}</p>
                          )}
                          {savedScore ? (
                            <>
                              <p>{t('predictions.yourPrediction', { score: savedScore })}</p>
                              {points !== undefined && points !== null && (
                                <p>{t('predictions.points', { points })}</p>
                              )}
                            </>
                          ) : (
                            <span className="status-locked">
                              {t('predictions.lockedNoPrediction')}
                            </span>
                          )}
                        </div>
                      ) : locked ? (
                        saved ? (
                          <span className="status-locked">
                            {t('predictions.predictionLocked')}
                          </span>
                        ) : (
                          <span className="status-locked">
                            {t('predictions.lockedNoPrediction')}
                          </span>
                        )
                      ) : changed ? (
                        complete ? (
                          <span className="status-unsaved">
                            {t('predictions.unsavedChanges')}
                          </span>
                        ) : (
                          <span className="status-unsaved">
                            {t('predictions.incomplete')}
                          </span>
                        )
                      ) : saved ? (
                        <span className="status-saved">
                          {t('predictions.saved')}
                        </span>
                      ) : (
                        <span className="status-pending">
                          {t('predictions.notFilled')}
                        </span>
                      )}
                    </div>
                  </article>
                )
              })}
            </section>

            {message && messageType === 'error' && (
              <p className="auth-message error">{message}</p>
            )}

            {(hasPendingSave || recentSaveFlash) && (
              <section
                className={[
                  'predictions-actions',
                  hasPendingSave ? 'predictions-actions--active' : '',
                  recentSaveFlash
                    ? 'predictions-actions--saved-flash'
                    : '',
                ]
                  .filter(Boolean)
                  .join(' ')}
                aria-live="polite"
              >
                <div className="predictions-actions-summary">
                  {recentSaveFlash ? (
                    <strong className="predictions-actions-confirm">
                      {t('predictions.savedFlash')}
                    </strong>
                  ) : (
                    <>
                      <strong>
                        {unsavedChangesCount}{' '}
                        {t(
                          selectPlural(
                            unsavedChangesCount,
                            'predictions.unsavedOne',
                            'predictions.unsavedMany',
                          ),
                        )}
                      </strong>
                      <span className="predictions-actions-detail">
                        {savedPredictionCount} {t('predictions.savedMany')}
                      </span>
                    </>
                  )}
                </div>

                {hasPendingSave && (
                  <button
                    type="button"
                    className="save-predictions-button"
                    disabled={saving || unsavedChangesCount === 0}
                    onClick={() => void handleSavePredictions()}
                  >
                    {saving
                      ? t('common.saving')
                      : t('predictions.saveButton')}
                  </button>
                )}
              </section>
            )}
          </>
        )}
      </main>

    </div>
  )
}
