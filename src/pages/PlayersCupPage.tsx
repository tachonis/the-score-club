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
import { t } from '../i18n'
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
      const notice = error ?? t('cup.refreshFailed')
      const hasVisibleState = snapshotRef.current !== null

      if (mode === 'background' && hasVisibleState) {
        setRefreshNotice(t('cup.autoRefreshFailed'))
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
          <p>{t('cup.loading')}</p>
        </section>
      )
    }

    if (errorMessage && !snapshot) {
      return (
        <section className="empty-state">
          <h2>{t('cup.loadFailed')}</h2>
          <p>{errorMessage}</p>
          <button
            type="button"
            className="league-refresh-button"
            onClick={() => void loadPage('initial')}
          >
            {t('common.refresh')}
          </button>
        </section>
      )
    }

    if (!snapshot) {
      return (
        <section className="empty-state">
          <h2>{t('cup.loadFailed')}</h2>
          <p>{t('cup.trySoon')}</p>
          <button
            type="button"
            className="league-refresh-button"
            onClick={() => void loadPage('initial')}
          >
            {t('common.refresh')}
          </button>
        </section>
      )
    }

    if (snapshot.cup) {
      if (!cupLiveDataIsComplete(snapshot)) {
        return (
          <section className="empty-state">
            <h2>{t('cup.incompleteTitle')}</h2>
            <p>
              {t('cup.incompleteBody')}
            </p>
            <button
              type="button"
              className="league-refresh-button"
              onClick={() => void loadPage('initial')}
            >
              {t('common.refresh')}
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
              <span className="matchday-status">{t('cup.completed')}</span>
              <h2>
                {t('cup.participated', {
                  count: snapshot.cup.participant_count,
                })}
              </h2>
              {snapshot.awards.length === 0 ? (
                <p className="cup-helper-note">
                  {t('cup.honoursUnavailable')}
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
              <span className="matchday-status">{t('cup.drawDone')}</span>
              <h2>
                {t('cup.participating', {
                  count: snapshot.cup.participant_count,
                })}
              </h2>
              <ul className="cup-prize-list">
                <li>
                  <span>{t('cup.winner')}</span>
                  <strong>+{snapshot.rewards.winner}</strong>
                </li>
                <li>
                  <span>{t('cup.finalist')}</span>
                  <strong>+{snapshot.rewards.finalist}</strong>
                </li>
                <li>
                  <span>{t('cup.semiFinalists')}</span>
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
          <h2>{t('cup.notConfiguredTitle')}</h2>
          <p>
            {t('cup.notConfiguredBody')}
          </p>
        </section>
      )
    }

    if (!snapshot.rankingMatchdaysComplete) {
      return (
        <section className="cup-status-card">
          <span className="matchday-status">
            {t('cup.drawPending')}
          </span>
          <p>
            {t('cup.startsAtMd3')}
          </p>
          {snapshot.viewerRank !== null && (
            <p className="cup-viewer-rank">
              {t('cup.yourRankNow')}{' '}
              <strong>{formatRankPosition(snapshot.viewerRank)}</strong>
            </p>
          )}
          <ol className="cup-timeline">
            <li>{t('cup.timelineRanking')}</li>
            <li>{t('cup.timelineDraw')}</li>
            <li>{t('cup.timelineKnockout')}</li>
          </ol>
        </section>
      )
    }

    return (
      <section className="cup-status-card">
        <span className="matchday-status">
          {t('cup.drawPending')}
        </span>
        <p>
          {t('cup.md2DonePendingDraw')}
        </p>
        {snapshot.activePlayerCount < MINIMUM_CUP_PARTICIPANTS && (
          <p className="cup-helper-note">
            {t('cup.needPlayers', { count: MINIMUM_CUP_PARTICIPANTS })}
          </p>
        )}
        {snapshot.viewerRank !== null && (
          <p className="cup-viewer-rank">
            {t('cup.yourRankNow')}{' '}
            <strong>{formatRankPosition(snapshot.viewerRank)}</strong>
          </p>
        )}
        <ul className="cup-prize-list">
          <li>
            <span>{t('cup.winner')}</span>
            <strong>+{snapshot.rewards.winner}</strong>
          </li>
          <li>
            <span>{t('cup.finalist')}</span>
            <strong>+{snapshot.rewards.finalist}</strong>
          </li>
          <li>
            <span>{t('cup.semiFinalists')}</span>
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
              {t('cup.intro')}
            </p>
          </div>

          <div className="cup-page-actions">
            <button
              type="button"
              className="cup-rules-button"
              onClick={() => setRulesOpen(true)}
            >
              {t('cup.rulesButton')}
            </button>
            <button
              type="button"
              className="cup-utility-button"
              onClick={() => void loadPage('manual')}
              disabled={loading || refreshing}
            >
              {refreshing ? t('common.refreshing') : t('common.refresh')}
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
