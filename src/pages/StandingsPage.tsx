import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
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
  { id: 'overall', label: 'Γενική' },
  { id: 'matchday', label: 'Ανά Αγωνιστική' },
  { id: 'knockout', label: 'Knockout' },
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
        setErrorMessage('Δεν ήταν δυνατή η αναγνώριση του χρήστη.')
        setLoadingOverall(false)
        return
      }

      setCurrentUserId(user.id)

      const { data, error } = await supabase.rpc('get_leaderboard')

      if (error) {
        setErrorMessage(
          `Δεν φορτώθηκε η βαθμολογία: ${error.message}`,
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
          `Δεν φορτώθηκαν οι αγωνιστικές: ${error.message}`,
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
          `Δεν φορτώθηκε η βαθμολογία αγωνιστικής: ${error.message}`,
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
          `Δεν φορτώθηκε η βαθμολογία νοκ-άουτ: ${error.message}`,
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
        : 'Ανά αγωνιστική'
      : view === 'knockout'
        ? 'Knockout'
        : 'Γενική κατάταξη'

  const introCopy =
    view === 'matchday'
      ? 'Η κατάταξη των παικτών για κάθε αγωνιστική της League Phase.'
      : view === 'knockout'
        ? 'Η κατάταξη από προβλέψεις στα Knockout Play-offs, τη Φάση των 16, τα Προημιτελικά, τα Ημιτελικά και τον Τελικό.'
        : 'Η συνολική κατάταξη των παικτών του The Score Club.'

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

          <h1>Βαθμολογία</h1>

          <p>{introCopy}</p>
        </section>

        <div
          className="tsc-standings-views"
          role="tablist"
          aria-label="Όψεις βαθμολογίας"
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
              aria-label="Αγωνιστικές League Phase"
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
            <p>Φόρτωση βαθμολογίας...</p>
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
                  {activeRows.length === 1 ? 'παίκτης' : 'παίκτες'}
                </strong>
              </div>
            </div>

            <div className="tsc-table-scroll">
              <div className="tsc-table-header">
                <span>{formatGreekAllCaps('Θέση')}</span>
                <span>{formatGreekAllCaps('Παίκτης')}</span>
                <span>{formatGreekAllCaps('Βαθμοί')}</span>
                <span>{formatGreekAllCaps('Ακριβή')}</span>
                <span>{formatGreekAllCaps('Σωστά')}</span>
              </div>

              <div className="tsc-table-body">
                {activeRows.length === 0 ? (
                  <div className="tsc-leaderboard-empty">
                    Δεν υπάρχουν ακόμη παίκτες στη βαθμολογία.
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
                            aria-label={`Προφίλ ${row.username}`}
                          >
                            <span>{row.username}</span>
                            {isCurrentUser ? <small>Εσύ</small> : null}
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
            <h2 id="standings-tiebreak-heading">Ισοβαθμία</h2>
            <p>Σε ισοβαθμία εφαρμόζονται διαδοχικά:</p>
            <ol>
              <li>περισσότερα ακριβή σκορ</li>
              <li>περισσότερα σωστά αποτελέσματα</li>
              <li>περισσότεροι βαθμοί στα νοκ-άουτ</li>
              <li>λιγότερες χαμένες προβλέψεις</li>
            </ol>
            <p>
              Αν παραμένει ισοβαθμία, οι παίκτες μοιράζονται την ίδια θέση.
            </p>
            <p>
              Οι βαθμοί στα νοκ-άουτ προέρχονται από προβλέψεις στα Knockout
              Play-offs, τη Φάση των 16, τα Προημιτελικά, τα Ημιτελικά και
              τον Τελικό. Δεν περιλαμβάνουν League Phase, Players Cup ή
              μακροχρόνιες προβλέψεις.
            </p>
            <p>
              Χαμένες προβλέψεις είναι τελειωμένοι αγώνες στους οποίους ο
              παίκτης δεν είχε πρόβλεψη.
            </p>
          </section>
        ) : null}

        {view === 'matchday' ? (
          <section
            className="tsc-tiebreak-note"
            aria-labelledby="standings-matchday-tiebreak-heading"
          >
            <h2 id="standings-matchday-tiebreak-heading">Ισοβαθμία</h2>
            <p>
              Μετρούν μόνο οι πόντοι προβλέψεων της επιλεγμένης αγωνιστικής
              της League Phase. Golden Match μετρά με τους ήδη διπλασιασμένους
              αποθηκευμένους πόντους. Μακροχρόνιες προβλέψεις, Players Cup και
              νοκ-άουτ δεν περιλαμβάνονται.
            </p>
            <p>Σε ισοβαθμία εφαρμόζονται διαδοχικά:</p>
            <ol>
              <li>περισσότερα ακριβή σκορ στην αγωνιστική</li>
              <li>περισσότερα σωστά αποτελέσματα στην αγωνιστική</li>
            </ol>
            <p>
              Αν παραμένει ισοβαθμία, οι παίκτες μοιράζονται την ίδια θέση.
            </p>
          </section>
        ) : null}

        {view === 'knockout' ? (
          <section
            className="tsc-tiebreak-note"
            aria-labelledby="standings-knockout-tiebreak-heading"
          >
            <h2 id="standings-knockout-tiebreak-heading">Ισοβαθμία</h2>
            <p>
              Μετρούν μόνο προβλέψεις στα Knockout Play-offs, τη Φάση των 16,
              τα Προημιτελικά, τα Ημιτελικά και τον Τελικό. League Phase,
              Players Cup και μακροχρόνιες προβλέψεις δεν περιλαμβάνονται.
            </p>
            <p>Σε ισοβαθμία εφαρμόζονται διαδοχικά:</p>
            <ol>
              <li>περισσότερα ακριβή σκορ στα νοκ-άουτ</li>
              <li>περισσότερα σωστά αποτελέσματα στα νοκ-άουτ</li>
              <li>λιγότερες χαμένες προβλέψεις στα νοκ-άουτ</li>
            </ol>
            <p>
              Αν παραμένει ισοβαθμία, οι παίκτες μοιράζονται την ίδια θέση.
            </p>
          </section>
        ) : null}
      </main>
    </div>
  )
}
