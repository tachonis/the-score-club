import { useCallback, useEffect, useRef, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { CupExcludedNote } from '../components/cup/CupExcludedNote'
import { CupHonours } from '../components/cup/CupHonours'
import { CupPersonalPath } from '../components/cup/CupPersonalPath'
import { CupPersonalTieCard } from '../components/cup/CupPersonalTieCard'
import { CupRoundStrip } from '../components/cup/CupRoundStrip'
import { CupRoundTies } from '../components/cup/CupRoundTies'
import { CupRulesModal } from '../components/cup/CupRulesModal'
import {
  DEFAULT_CUP_REWARDS,
  MINIMUM_CUP_PARTICIPANTS,
  cupLiveDataIsComplete,
  defaultSelectedRoundNumber,
  findViewerParticipant,
  formatRankPosition,
  isCupRoundNumber,
  loadPlayersCupSnapshot,
  type PlayersCupSnapshot,
} from '../lib/cup'

type PlayersCupPageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type CupLoadMode = 'initial' | 'manual' | 'background'

const CUP_POLL_MS = 30_000

export function PlayersCupPage({
  username,
  role,
  onNavigate,
  onLogout,
}: PlayersCupPageProps) {
  const [snapshot, setSnapshot] = useState<PlayersCupSnapshot | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')
  const [refreshNotice, setRefreshNotice] = useState('')
  const [manualRoundNumber, setManualRoundNumber] = useState<number | null>(
    null,
  )
  const [rulesOpen, setRulesOpen] = useState(false)
  const snapshotRef = useRef<PlayersCupSnapshot | null>(null)
  const inFlightRef = useRef(false)
  const loadGenerationRef = useRef(0)

  snapshotRef.current = snapshot

  const loadPage = useCallback(async (mode: CupLoadMode) => {
    if (inFlightRef.current && mode === 'background') {
      return
    }

    const generation = ++loadGenerationRef.current
    inFlightRef.current = true

    if (mode === 'initial') {
      setLoading(true)
    }

    if (mode === 'manual') {
      setRefreshing(true)
      setRefreshNotice('')
    }

    const { snapshot: nextSnapshot, error } = await loadPlayersCupSnapshot()

    if (generation !== loadGenerationRef.current) {
      return
    }

    inFlightRef.current = false

    if (error || !nextSnapshot) {
      const notice = error ?? 'Η ανανέωση δεν ολοκληρώθηκε.'
      const hasVisibleState = snapshotRef.current !== null

      if (mode === 'background' && hasVisibleState) {
        setRefreshNotice('Η αυτόματη ανανέωση απέτυχε.')
      } else if (mode === 'manual' && hasVisibleState) {
        setRefreshNotice(notice)
      } else {
        setErrorMessage(notice)
        if (mode === 'initial') {
          setSnapshot(null)
        }
      }
    } else {
      setSnapshot(nextSnapshot)
      setErrorMessage('')
      setRefreshNotice('')
    }

    setLoading(false)
    setRefreshing(false)
  }, [])

  useEffect(() => {
    void loadPage('initial')

    return () => {
      loadGenerationRef.current += 1
    }
  }, [loadPage])

  useEffect(() => {
    const refreshOnFocus = () => {
      void loadPage('background')
    }

    window.addEventListener('focus', refreshOnFocus)

    return () => {
      window.removeEventListener('focus', refreshOnFocus)
    }
  }, [loadPage])

  useEffect(() => {
    if (snapshot?.cup?.status !== 'active') {
      return
    }

    const pollId = window.setInterval(() => {
      void loadPage('background')
    }, CUP_POLL_MS)

    return () => {
      window.clearInterval(pollId)
    }
  }, [loadPage, snapshot?.cup?.status])

  const selectedRoundNumber =
    manualRoundNumber && isCupRoundNumber(manualRoundNumber)
      ? manualRoundNumber
      : snapshot
        ? defaultSelectedRoundNumber(
            snapshot.rounds,
            snapshot.ties,
            snapshot.cup?.status,
          )
        : 1

  const renderBody = () => {
    if (loading && !snapshot) {
      return (
        <section className="app-loading-inline">
          <LoadingMark />
          <p>Φόρτωση Κυπέλλου...</p>
        </section>
      )
    }

    if (errorMessage && !snapshot) {
      return (
        <section className="empty-state">
          <h2>Δεν φορτώθηκε το Κύπελλο</h2>
          <p>{errorMessage}</p>
          <button
            type="button"
            className="league-refresh-button"
            onClick={() => void loadPage('initial')}
          >
            Ανανέωση
          </button>
        </section>
      )
    }

    if (!snapshot) {
      return (
        <section className="empty-state">
          <h2>Δεν φορτώθηκε το Κύπελλο</h2>
          <p>Δοκίμασε ξανά σε λίγο.</p>
          <button
            type="button"
            className="league-refresh-button"
            onClick={() => void loadPage('initial')}
          >
            Ανανέωση
          </button>
        </section>
      )
    }

    if (snapshot.cup) {
      if (!cupLiveDataIsComplete(snapshot)) {
        return (
          <section className="empty-state">
            <h2>Τα δεδομένα του Κυπέλλου είναι ελλιπή.</h2>
            <p>
              Η κλήρωση υπάρχει, αλλά δεν φορτώθηκαν οι γύροι ή οι αγώνες.
            </p>
            <button
              type="button"
              className="league-refresh-button"
              onClick={() => void loadPage('initial')}
            >
              Ανανέωση
            </button>
          </section>
        )
      }

      const viewerParticipant = findViewerParticipant(
        snapshot.participants,
        snapshot.viewerUserId,
      )
      const isCompleted = snapshot.cup.status === 'completed'
      const selectedRound =
        snapshot.rounds.find(
          (round) => round.round_number === selectedRoundNumber,
        ) ?? null

      return (
        <>
          {isCompleted ? (
            <section className="cup-completed-banner">
              <span className="matchday-status">Ολοκληρώθηκε</span>
              <h2>
                {snapshot.cup.participant_count} παίκτες συμμετείχαν στο
                Players Cup.
              </h2>
              {snapshot.awards.length === 0 ? (
                <p className="cup-helper-note">
                  Τα στοιχεία των επάθλων δεν είναι διαθέσιμα.
                </p>
              ) : null}
            </section>
          ) : null}

          {isCompleted ? <CupHonours snapshot={snapshot} /> : null}

          <CupPersonalTieCard
            snapshot={snapshot}
            selectedRoundNumber={selectedRoundNumber}
          />

          <CupRoundStrip
            selectedRoundNumber={selectedRoundNumber}
            onSelect={(roundNumber) => setManualRoundNumber(roundNumber)}
          />

          <CupRoundTies
            snapshot={snapshot}
            selectedRoundNumber={selectedRoundNumber}
            viewerParticipantId={viewerParticipant?.id ?? null}
          />

          <CupExcludedNote
            excludedMatches={snapshot.excludedMatches}
            roundId={selectedRound?.id ?? null}
          />

          <CupPersonalPath snapshot={snapshot} />

          {isCompleted ? null : (
            <section className="cup-status-card cup-rewards-footer">
              <span className="matchday-status">Η κλήρωση ολοκληρώθηκε</span>
              <h2>
                {snapshot.cup.participant_count} παίκτες συμμετέχουν στο Players
                Cup.
              </h2>
              <ul className="cup-prize-list">
                <li>
                  <span>Νικητής</span>
                  <strong>+{snapshot.rewards.winner}</strong>
                </li>
                <li>
                  <span>Φιναλίστ</span>
                  <strong>+{snapshot.rewards.finalist}</strong>
                </li>
                <li>
                  <span>Ημιτελικά</span>
                  <strong>+{snapshot.rewards.semiFinalist}</strong>
                </li>
              </ul>
            </section>
          )}
        </>
      )
    }

    if (!snapshot.rankingMatchdaysExist) {
      return (
        <section className="empty-state">
          <h2>Το Κύπελλο δεν έχει ρυθμιστεί ακόμη</h2>
          <p>
            Δεν βρέθηκαν η 1η και η 2η αγωνιστική της League Phase.
          </p>
        </section>
      )
    }

    if (!snapshot.rankingMatchdaysComplete) {
      return (
        <section className="cup-status-card">
          <span className="matchday-status">
            Η κλήρωση δεν έχει πραγματοποιηθεί ακόμη
          </span>
          <p>
            Το Κύπελλο ξεκινά από την 3η αγωνιστική. Η κλήρωση θα
            πραγματοποιηθεί μετά την ολοκλήρωση της 2ης αγωνιστικής. Οι 8
            πρώτοι της βαθμολογίας θα είναι seeded.
          </p>
          {snapshot.viewerRank !== null && (
            <p className="cup-viewer-rank">
              Η θέση σου τώρα:{' '}
              <strong>{formatRankPosition(snapshot.viewerRank)}</strong>
            </p>
          )}
          <ol className="cup-timeline">
            <li>1η–2η αγωνιστική</li>
            <li>Κλήρωση</li>
            <li>3η–8η αγωνιστική / νοκ-άουτ</li>
          </ol>
        </section>
      )
    }

    return (
      <section className="cup-status-card">
        <span className="matchday-status">
          Η κλήρωση δεν έχει πραγματοποιηθεί ακόμη
        </span>
        <p>
          Η 2η αγωνιστική ολοκληρώθηκε. Η κλήρωση του Players Cup δεν έχει
          πραγματοποιηθεί ακόμη.
        </p>
        {snapshot.activePlayerCount < MINIMUM_CUP_PARTICIPANTS && (
          <p className="cup-helper-note">
            Απαιτούνται τουλάχιστον {MINIMUM_CUP_PARTICIPANTS} ενεργοί παίκτες
            για να πραγματοποιηθεί η κλήρωση.
          </p>
        )}
        {snapshot.viewerRank !== null && (
          <p className="cup-viewer-rank">
            Η θέση σου τώρα:{' '}
            <strong>{formatRankPosition(snapshot.viewerRank)}</strong>
          </p>
        )}
        <ul className="cup-prize-list">
          <li>
            <span>Νικητής</span>
            <strong>+{snapshot.rewards.winner}</strong>
          </li>
          <li>
            <span>Φιναλίστ</span>
            <strong>+{snapshot.rewards.finalist}</strong>
          </li>
          <li>
            <span>Ημιτελικά</span>
            <strong>+{snapshot.rewards.semiFinalist}</strong>
          </li>
        </ul>
      </section>
    )
  }

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="players-cup"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="cup-page-main">
        <section className="cup-page-intro">
          <div>
            <p className="dashboard-eyebrow">Champions League 2026/27</p>
            <h1>Players Cup</h1>
            <p>
              Νοκ-άουτ αναμετρήσεις μεταξύ των παικτών, από την 3η έως την
              8η αγωνιστική.
            </p>
          </div>

          <div className="cup-page-actions">
            <button
              type="button"
              className="cup-rules-button"
              onClick={() => setRulesOpen(true)}
            >
              Κανόνες Κυπέλλου
            </button>
            <button
              type="button"
              className="cup-utility-button"
              onClick={() => void loadPage('manual')}
              disabled={loading || refreshing}
            >
              {refreshing ? 'Ανανέωση...' : 'Ανανέωση'}
            </button>
          </div>
        </section>

        {refreshNotice ? (
          <p className="cup-refresh-notice" role="status">
            {refreshNotice}
          </p>
        ) : null}

        {renderBody()}
      </main>

      {rulesOpen ? (
        <CupRulesModal
          rewards={snapshot?.rewards ?? DEFAULT_CUP_REWARDS}
          onClose={() => setRulesOpen(false)}
        />
      ) : null}
    </div>
  )
}
