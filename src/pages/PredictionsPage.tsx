import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LongTermPredictionsSection } from '../components/LongTermPredictionsSection'
import { supabase } from '../lib/supabase'
import { getCompactTeamName } from '../lib/teamDisplayName'

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

  const [goldenMatches, setGoldenMatches] = useState<
    Record<number, number>
  >({})

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [savingGoldenMatchId, setSavingGoldenMatchId] = useState<
    number | null
  >(null)
  const [now, setNow] = useState(() => Date.now())
  const [message, setMessage] = useState('')

  const [messageType, setMessageType] = useState<
    'success' | 'error'
  >('success')
  const [recentSaveFlash, setRecentSaveFlash] = useState(false)
  const saveFlashTimeoutRef = useRef<number | null>(null)
  const awayInputRefs = useRef<Record<number, HTMLInputElement | null>>({})

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
        setMessage('Δεν ήταν δυνατή η αναγνώριση του χρήστη.')
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
          `Δεν φορτώθηκαν οι αγώνες: ${matchesError.message}`,
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
          `Δεν φορτώθηκαν οι προβλέψεις: ${predictionsError.message}`,
        )
        setLoading(false)
        return
      }

      if (goldenMatchesResult.error) {
        setMessageType('error')
        setMessage(
          `Δεν φορτώθηκαν οι επιλογές Golden Match: ${goldenMatchesResult.error.message}`,
        )
        setLoading(false)
        return
      }

      const loadedPredictions =
        (predictionsData ?? []) as StoredPrediction[]

      const predictionValues: Record<number, PredictionValues> = {}

      loadedPredictions.forEach((prediction) => {
        predictionValues[prediction.match_id] = {
          home: String(prediction.predicted_home_score),
          away: String(prediction.predicted_away_score),
        }
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
      setGoldenMatches(goldenMatchValues)

      if (loadedMatches.length > 0) {
        setSelectedMatchdayId(loadedMatches[0].matchday_id)
      }

      setLoading(false)
    }

    void loadPageData()
  }, [])

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 30_000)
    return () => window.clearInterval(timer)
  }, [])

  const matchdays = useMemo(() => {
    const uniqueMatchdays = new Map<number, Matchday>()

    matches.forEach((match) => {
      uniqueMatchdays.set(match.matchday.id, match.matchday)
    })

    return Array.from(uniqueMatchdays.values()).sort((a, b) => {
      return (a.matchday_number ?? 0) - (b.matchday_number ?? 0)
    })
  }, [matches])

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

  const goldenMatchIsAvailable =
    (selectedMatchday?.matchday_number ?? 0) >= 2
  const selectedGoldenMatchId = selectedMatchdayId === null
    ? null
    : (goldenMatches[selectedMatchdayId] ?? null)

  const isMatchLocked = (match: Match) => {
    return (
      match.status !== 'scheduled' ||
      now >= new Date(match.kickoff_at).getTime()
    )
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

    if (team === 'home' && value.length === 1) {
      awayInputRefs.current[matchId]?.focus()
    }
  }

  const handleGoldenMatchSelection = async (match: Match) => {
    if (!goldenMatchIsAvailable) {
      setMessageType('error')
      setMessage('Το Golden Match ενεργοποιείται από τη 2η αγωνιστική.')
      return
    }

    if (isMatchLocked(match)) {
      setMessageType('error')
      setMessage('Το συγκεκριμένο παιχνίδι έχει ήδη κλειδώσει.')
      return
    }

    if (goldenMatchIsLocked) {
      setMessageType('error')
      setMessage(
        'Το Golden Match αυτής της αγωνιστικής έχει κλειδώσει μετά το kickoff.',
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
        'Golden Match is available from Matchday 2':
          'Το Golden Match ενεργοποιείται από τη 2η αγωνιστική.',
        'Golden Match must be selected before kickoff':
          'Η επιλογή πρέπει να γίνει πριν από το kickoff.',
        'Golden Match is locked after its kickoff':
          'Το Golden Match έχει κλειδώσει και δεν μπορεί πλέον να αλλάξει.',
      }

      setMessageType('error')
      setMessage(
        knownMessages[error.message] ??
          `Δεν αποθηκεύτηκε το Golden Match: ${error.message}`,
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
        ? 'Το Golden Match αποθηκεύτηκε.'
        : 'Το Golden Match αντικαταστάθηκε επιτυχώς.',
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
      setMessage('Δεν ήταν δυνατή η αναγνώριση του χρήστη.')
      setSaving(false)
      return
    }

    const predictionsToSave = selectedMatches
      .filter((match) => !isMatchLocked(match))
      .filter((match) => hasCompletePrediction(match.id))
      .filter((match) => hasUnsavedChanges(match.id))
      .map((match) => ({
        user_id: user.id,
        match_id: match.id,
        predicted_home_score: Number(
          predictions[match.id].home,
        ),
        predicted_away_score: Number(
          predictions[match.id].away,
        ),
        updated_at: new Date().toISOString(),
      }))

    if (predictionsToSave.length === 0) {
      setMessageType('error')

      if (completedPredictions === 0) {
        setMessage(
          'Συμπλήρωσε τουλάχιστον μία πρόβλεψη πριν από την αποθήκευση.',
        )
      } else {
        setMessage('Δεν υπάρχουν νέες αλλαγές για αποθήκευση.')
      }

      setSaving(false)
      return
    }

    const { error } = await supabase
      .from('predictions')
      .upsert(predictionsToSave, {
        onConflict: 'user_id,match_id',
      })

    if (error) {
      setMessageType('error')
      setMessage(`Δεν αποθηκεύτηκαν οι προβλέψεις: ${error.message}`)
      setSaving(false)
      return
    }

    const updatedSavedPredictions = {
      ...savedPredictions,
    }

    predictionsToSave.forEach((prediction) => {
      updatedSavedPredictions[prediction.match_id] = {
        home: String(prediction.predicted_home_score),
        away: String(prediction.predicted_away_score),
      }
    })

    setSavedPredictions(updatedSavedPredictions)

    setMessageType('success')
    setMessage(
      `Αποθηκεύτηκαν ${predictionsToSave.length} προβλέψεις.`,
    )

    setRecentSaveFlash(true)
    if (saveFlashTimeoutRef.current !== null) {
      window.clearTimeout(saveFlashTimeoutRef.current)
    }
    saveFlashTimeoutRef.current = window.setTimeout(() => {
      setRecentSaveFlash(false)
      setMessage('')
      saveFlashTimeoutRef.current = null
    }, 2600)

    setSaving(false)
  }

  const hasPendingSave = unsavedChangesCount > 0 || saving

  const formatMatchDate = (kickoffAt: string) => {
    return new Intl.DateTimeFormat('el-GR', {
      weekday: 'short',
      day: '2-digit',
      month: 'long',
    }).format(new Date(kickoffAt))
  }

  const formatMatchTime = (kickoffAt: string) => {
    return new Intl.DateTimeFormat('el-GR', {
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

            <h1>Αγώνες &amp; Προβλέψεις</h1>

            <p>
              Συμπλήρωσε το προβλεπόμενο σκορ κάθε αγώνα πριν
              από την προγραμματισμένη ώρα έναρξης.
            </p>
          </div>

          <div className="predictions-counter">
            <span>Αποθηκευμένες προβλέψεις</span>

            <strong>
              {savedPredictionCount} / {selectedMatches.length}
            </strong>
          </div>
        </section>

        <LongTermPredictionsSection />

        {loading ? (
          <section className="app-loading-inline">
            <div className="loading-mark">TSC</div>
            <p>Φόρτωση αγώνων...</p>
          </section>
        ) : matches.length === 0 ? (
          <section className="empty-state">
            <h2>Δεν υπάρχουν αγώνες</h2>

            <p>
              Οι αγώνες θα εμφανιστούν όταν προστεθούν από τη
              διαχείριση.
            </p>
          </section>
        ) : (
          <>
            <section className="matchday-selector">
              <div className="matchday-tabs" role="tablist">
                {matchdays.map((matchday) => (
                  <button
                    key={matchday.id}
                    type="button"
                    className={`matchday-tab ${
                      selectedMatchdayId === matchday.id
                        ? 'active'
                        : ''
                    }`}
                    onClick={() =>
                      setSelectedMatchdayId(matchday.id)
                    }
                  >
                    {matchday.matchday_number
                      ? `${matchday.matchday_number}η αγωνιστική`
                      : matchday.name}
                  </button>
                ))}
              </div>
            </section>

            <section className="selected-matchday-info">
              <div>
                <span>League Phase</span>

                <h2>
                  {selectedMatchday?.name ??
                    'Επιλεγμένη αγωνιστική'}
                </h2>
              </div>

              <p className="matchday-timezone-note">
                Οι ώρες εμφανίζονται αυτόματα στην τοπική ώρα
                της συσκευής σου.
              </p>
            </section>

            <section
              className={`golden-match-guide ${
                goldenMatchIsAvailable ? '' : 'inactive'
              } ${goldenMatchIsLocked ? 'locked' : ''}`}
            >
              <div className="golden-match-guide-icon" aria-hidden="true">
                ★
              </div>

              <div className="golden-match-guide-copy">
                <span>GOLDEN MATCH · ΔΙΠΛΟΙ ΒΑΘΜΟΙ</span>
                <h3>
                  {goldenMatchIsAvailable
                    ? 'Διάλεξε ένα παιχνίδι της αγωνιστικής'
                    : 'Διαθέσιμο από τη 2η αγωνιστική'}
                </h3>
                <p>
                  {goldenMatchIsAvailable
                    ? 'Ακριβές σκορ 10 βαθμοί, σωστό 1-X-2 4 βαθμοί. Μπορείς να αλλάξεις επιλογή πριν από το kickoff του επιλεγμένου αγώνα· η νέα επιλογή αντικαθιστά την προηγούμενη.'
                    : 'Το δικαίωμα της 1ης αγωνιστικής δεν μεταφέρεται. Από τη 2η αγωνιστική έχεις μία ανεξάρτητη επιλογή ανά αγωνιστική.'}
                </p>
              </div>

              {goldenMatchIsAvailable && (
                <div className="golden-match-current">
                  <span>
                    {goldenMatchIsLocked
                      ? 'ΚΛΕΙΔΩΜΕΝΟ'
                      : 'ΤΡΕΧΟΥΣΑ ΕΠΙΛΟΓΗ'}
                  </span>
                  <strong>
                    {selectedGoldenMatch
                      ? `${selectedGoldenMatch.home_team.name} – ${selectedGoldenMatch.away_team.name}`
                      : 'Δεν έχει επιλεγεί αγώνας'}
                  </strong>
                </div>
              )}

              {goldenMatchMissingSavedPrediction && selectedGoldenMatch && (
                <p
                  className="golden-match-prediction-warning"
                  role="status"
                >
                  Έχεις επιλέξει αυτόν τον αγώνα ως Golden Match, αλλά
                  δεν έχεις αποθηκεύσει ακόμη πρόβλεψη σκορ. Συμπλήρωσε
                  το σκορ και πάτησε «Αποθήκευση προβλέψεων».
                </p>
              )}
            </section>

            <section className="matches-list">
              {selectedMatches.map((match) => {
                const prediction = predictions[match.id] ?? {
                  home: '',
                  away: '',
                }

                const locked = isMatchLocked(match)
                const complete = hasCompletePrediction(match.id)
                const saved = hasSavedPrediction(match.id)
                const changed = hasUnsavedChanges(match.id)
                const goldenSelected =
                  selectedGoldenMatchId === match.id
                const matchLocked = isMatchLocked(match)

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
                            aria-label={matchLocked ? 'Golden Match κλειδωμένο' : 'Golden Match επιλεγμένο'}
                          >
                            ★
                          </span>
                        ) : !matchLocked && !goldenMatchIsLocked ? (
                          <button
                            type="button"
                            className="match-meta-golden-button"
                            disabled={savingGoldenMatchId !== null}
                            onClick={() => void handleGoldenMatchSelection(match)}
                            aria-label={`${selectedGoldenMatchId === null ? 'Επιλογή' : 'Αντικατάσταση'} Golden Match: ${match.home_team.name} - ${match.away_team.name}`}
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
                              ? 'Golden Match κλειδωμένο'
                              : 'Golden Match επιλεγμένο'}
                          </span>
                        ) : (
                          <button
                            type="button"
                            className="golden-match-button"
                            disabled={savingGoldenMatchId !== null}
                            onClick={() =>
                              void handleGoldenMatchSelection(match)
                            }
                            aria-label={`${
                              selectedGoldenMatchId === null
                                ? 'Επιλογή'
                                : 'Αντικατάσταση'
                            } Golden Match: ${match.home_team.name} - ${match.away_team.name}`}
                          >
                            <span aria-hidden="true">☆</span>
                            {savingGoldenMatchId === match.id
                              ? 'Αποθήκευση...'
                              : selectedGoldenMatchId === null
                                ? 'Επιλογή Golden Match'
                                : 'Αντικατάσταση Golden Match'}
                          </button>
                        )}
                      </div>
                    )}

                    {goldenSelected && !saved && (
                      <p
                        className="golden-match-prediction-warning golden-match-prediction-warning--card"
                        role="status"
                      >
                        Έχεις επιλέξει αυτόν τον αγώνα ως Golden Match,
                        αλλά δεν έχεις αποθηκεύσει ακόμη πρόβλεψη σκορ.
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
                        <input
                          type="text"
                          inputMode="numeric"
                          maxLength={2}
                          value={prediction.home}
                          disabled={locked}
                          onFocus={(e) => e.target.select()}
                          onChange={(event) =>
                            handleScoreChange(
                              match.id,
                              'home',
                              event.target.value,
                            )
                          }
                          aria-label={`Γκολ ${match.home_team.name}`}
                        />

                        <span>:</span>

                        <input
                          ref={(el) => { awayInputRefs.current[match.id] = el }}
                          type="text"
                          inputMode="numeric"
                          maxLength={2}
                          value={prediction.away}
                          disabled={locked}
                          onFocus={(e) => e.target.select()}
                          onChange={(event) =>
                            handleScoreChange(
                              match.id,
                              'away',
                              event.target.value,
                            )
                          }
                          aria-label={`Γκολ ${match.away_team.name}`}
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
                      {locked ? (
                        saved ? (
                          <span className="status-locked">
                            Η αποθηκευμένη πρόβλεψη έχει κλειδώσει
                          </span>
                        ) : (
                          <span className="status-locked">
                            Ο αγώνας έχει κλειδώσει χωρίς πρόβλεψη
                          </span>
                        )
                      ) : changed ? (
                        complete ? (
                          <span className="status-unsaved">
                            Υπάρχουν μη αποθηκευμένες αλλαγές
                          </span>
                        ) : (
                          <span className="status-unsaved">
                            Η πρόβλεψη δεν είναι ολοκληρωμένη
                          </span>
                        )
                      ) : saved ? (
                        <span className="status-saved">
                          Η πρόβλεψη έχει αποθηκευτεί
                        </span>
                      ) : (
                        <span className="status-pending">
                          Δεν έχει συμπληρωθεί πρόβλεψη
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
                      ✓ Αποθηκεύτηκε
                    </strong>
                  ) : (
                    <>
                      <strong>
                        {unsavedChangesCount}{' '}
                        {unsavedChangesCount === 1
                          ? 'μη αποθηκευμένη'
                          : 'μη αποθηκευμένες'}
                      </strong>
                      <span className="predictions-actions-detail">
                        {savedPredictionCount} αποθηκευμένες
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
                      ? 'Αποθήκευση...'
                      : 'Αποθήκευση προβλέψεων'}
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
