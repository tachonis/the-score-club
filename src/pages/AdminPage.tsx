import { useEffect, useMemo, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { AdminCupPanel } from '../components/cup/AdminCupPanel'
import { AdminNotificationsPanel } from '../components/AdminNotificationsPanel'
import { LongTermOutcomesPanel } from '../components/LongTermOutcomesPanel'
import {
  compareMatchdays,
  formatMatchdayLabel,
  isFinalStage,
  isLeaguePhaseStage,
} from '../lib/stages'
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
  scheduled: 'Προγραμματισμένος',
  live: 'Σε εξέλιξη',
  finished: 'Ολοκληρωμένος',
  postponed: 'Αναβλήθηκε',
  cancelled: 'Ακυρώθηκε',
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
  const [outcomesRefreshKey, setOutcomesRefreshKey] = useState(0)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )

  const loadMatches = async (preferredMatchdayId?: number | null) => {
    setLoading(true)

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
      setMessage(`Δεν φορτώθηκαν οι αγώνες: ${error.message}`)
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
    if (!/^\d{0,2}$/.test(value)) return

    setDrafts((current) => ({
      ...current,
      [matchId]: {
        ...(current[matchId] ?? { home: '', away: '' }),
        [side]: value,
      },
    }))
  }

  const handleSaveResult = async (match: AdminMatch) => {
    const draft = drafts[match.id]

    if (!draft || draft.home === '' || draft.away === '') {
      setMessageType('error')
      setMessage('Συμπλήρωσε και τα δύο πεδία σκορ 90 λεπτών.')
      return
    }

    setSavingMatchId(match.id)
    setMessage('')

    const { data, error } = await supabase.rpc('set_match_result', {
      p_match_id: match.id,
      p_home_score: Number(draft.home),
      p_away_score: Number(draft.away),
    })

    if (error) {
      setMessageType('error')
      setMessage(`Δεν αποθηκεύτηκε το αποτέλεσμα: ${error.message}`)
      setSavingMatchId(null)
      return
    }

    const result = (data?.[0] ?? null) as ResultResponse | null

    setMessageType('success')
    setMessage(
      `Το ${match.home_team.name} – ${match.away_team.name} αποθηκεύτηκε. ` +
        `${result?.scored_predictions ?? 0} προβλέψεις ελέγχθηκαν, ` +
        `${result?.changed_predictions ?? 0} βαθμολογίες άλλαξαν.`,
    )

    await loadMatches(selectedMatchdayId)
    setOutcomesRefreshKey((current) => current + 1)
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
    return new Intl.DateTimeFormat('el-GR', {
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
            <p className="dashboard-eyebrow">Ασφαλής καταχώριση</p>
            <h1>Διαχείριση αποτελεσμάτων</h1>
            <p>
              Καταχώρισε ή διόρθωσε σκορ. Η βαθμολογία επανυπολογίζεται
              αυτόματα.
            </p>
          </div>

          {matchdays.length > 0 && (
            <label className="admin-matchday-select">
              <span>Φάση</span>
              <select
                value={selectedMatchdayId ?? ''}
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

        <AdminCupPanel />

        <AdminNotificationsPanel />

        <LongTermOutcomesPanel refreshKey={outcomesRefreshKey} />

        {loading ? (
          <section className="app-loading-inline">
            <LoadingMark />
            <p>Φόρτωση αγώνων...</p>
          </section>
        ) : selectedMatches.length === 0 ? (
          <section className="empty-state">
            <h2>Δεν υπάρχουν αγώνες</h2>
            <p>Δεν βρέθηκαν αγώνες για την επιλεγμένη φάση.</p>
          </section>
        ) : (
          <section className="admin-matches-list">
            <div className="admin-scoring-notes">
              <p>Καταχώρησε το σκορ των 90 λεπτών + καθυστερήσεων.</p>
              {showKnockoutScoringNote && (
                <p>
                  Σε νοκ-άουτ αγώνες δεν υπολογίζονται παράταση ή πέναλτι.
                </p>
              )}
              {showFinalScoringNote && (
                <p className="admin-final-note">
                  Ο Τελικός βαθμολογείται x2: 10 βαθμοί για ακριβές σκορ, 4
                  για σωστό αποτέλεσμα, 0 για λάθος.
                </p>
              )}
            </div>

            {selectedMatches.map((match) => {
              const draft = drafts[match.id] ?? { home: '', away: '' }
              const isSaving = savingMatchId === match.id

              return (
                <article className="admin-match-card" key={match.id}>
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
                        onChange={(event) =>
                          handleScoreChange(match.id, 'home', event.target.value)
                        }
                        aria-label={`Σκορ 90 λεπτών ${match.home_team.name}`}
                      />
                      <span>:</span>
                      <input
                        type="text"
                        inputMode="numeric"
                        maxLength={2}
                        value={draft.away}
                        onChange={(event) =>
                          handleScoreChange(match.id, 'away', event.target.value)
                        }
                        aria-label={`Σκορ 90 λεπτών ${match.away_team.name}`}
                      />
                    </div>
                    <strong>{match.away_team.name}</strong>
                  </div>

                  <button
                    type="button"
                    className="admin-save-button"
                    disabled={savingMatchId !== null}
                    onClick={() => void handleSaveResult(match)}
                  >
                    {isSaving
                      ? 'Αποθήκευση...'
                      : match.status === 'finished'
                        ? 'Διόρθωση αποτελέσματος'
                        : 'Αποθήκευση αποτελέσματος'}
                  </button>
                </article>
              )
            })}
          </section>
        )}
      </main>

    </div>
  )
}
