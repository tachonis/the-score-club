import { useCallback, useEffect, useState } from 'react'
import { dateLocale, t } from '../../i18n'
import {
  MINIMUM_CUP_PARTICIPANTS,
  loadPlayersCupSnapshot,
  type PlayersCupSnapshot,
} from '../../lib/cup'
import { supabase } from '../../lib/supabase'

type ConfirmingAction = 'draw' | 'recompute' | null

type AdminCupPanelProps = {
  refreshKey?: number
}

export function AdminCupPanel({ refreshKey = 0 }: AdminCupPanelProps) {
  const [snapshot, setSnapshot] = useState<PlayersCupSnapshot | null>(null)
  const [loading, setLoading] = useState(true)
  const [busyAction, setBusyAction] = useState<ConfirmingAction>(null)
  const [confirming, setConfirming] = useState<ConfirmingAction>(null)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )

  const loadPanel = useCallback(async () => {
    setLoading(true)

    const { snapshot: nextSnapshot, error } = await loadPlayersCupSnapshot()

    if (error) {
      setMessageType('error')
      setMessage(error)
      setSnapshot(null)
    } else {
      setSnapshot(nextSnapshot)
    }

    setLoading(false)
  }, [])

  useEffect(() => {
    void loadPanel()
  }, [loadPanel, refreshKey])

  const reloadSnapshot = async () => {
    const { snapshot: nextSnapshot, error } = await loadPlayersCupSnapshot()

    if (error || !nextSnapshot) {
      setMessageType('error')
      setMessage(error ?? t('adminCup.commandNoReload'))
      return null
    }

    setSnapshot(nextSnapshot)
    return nextSnapshot
  }

  const handleDraw = async () => {
    setBusyAction('draw')
    setMessage('')

    const { error } = await supabase.rpc('create_players_cup', {
      p_dry_run: false,
    })

    const nextSnapshot = await reloadSnapshot()

    if (nextSnapshot?.cup) {
      setConfirming(null)
      setBusyAction(null)
      setMessageType('success')
      setMessage(
        error ? t('adminCup.alreadyDrawn') : t('adminCup.drawOk'),
      )
      return
    }

    setMessageType('error')
    setMessage(
      error
        ? t('adminCup.drawFailed', { detail: error.message })
        : t('adminCup.drawOkMissing'),
    )
    setBusyAction(null)
  }

  const handleRecompute = async () => {
    setBusyAction('recompute')
    setMessage('')

    const { error } = await supabase.rpc('recompute_players_cup')

    if (error) {
      setMessageType('error')
      setMessage(t('adminCup.recomputeFailed', { detail: error.message }))
      setBusyAction(null)
      return
    }

    const nextSnapshot = await reloadSnapshot()

    if (nextSnapshot) {
      setConfirming(null)
      setMessageType('success')
      setMessage(t('adminCup.recomputeOk'))
    }

    setBusyAction(null)
  }

  const formatCreatedAt = (value: string) => {
    return new Intl.DateTimeFormat(dateLocale, {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(value))
  }

  const cup = snapshot?.cup ?? null
  const rankingReady = Boolean(snapshot?.rankingMatchdaysComplete)
  const enoughPlayers =
    (snapshot?.activePlayerCount ?? 0) >= MINIMUM_CUP_PARTICIPANTS
  const canDraw = !cup && rankingReady && enoughPlayers
  const isBusy = busyAction !== null

  let statusLabel = t('common.loading')
  let helper = ''

  if (!loading && !snapshot && messageType === 'error') {
    statusLabel = t('adminCup.loadFailed')
  } else if (cup) {
    statusLabel = t('adminCup.drawDone')
  } else if (!snapshot?.rankingMatchdaysExist) {
    statusLabel = t('adminCup.noMatchdays')
    helper = t('adminCup.drawWhenMd12')
  } else if (!rankingReady) {
    statusLabel = t('adminCup.md2Incomplete')
    helper = t('adminCup.drawWhenMd12')
  } else if (!enoughPlayers) {
    statusLabel = t('adminCup.notEnoughPlayers')
    helper = t('adminCup.needPlayersNow', {
      min: MINIMUM_CUP_PARTICIPANTS,
      count: snapshot?.activePlayerCount ?? 0,
    })
  } else {
    statusLabel = t('adminCup.ready')
    helper = t('adminCup.drawFinal')
  }

  return (
    <section className="admin-cup-panel">
      <div className="admin-cup-panel-heading">
        <div>
          <p className="dashboard-eyebrow">Players Cup</p>
          <h2>{t('adminCup.heading')}</h2>
        </div>
        <span className="matchday-status">{statusLabel}</span>
      </div>

      {message && (
        <p
          className={`auth-message ${
            messageType === 'error' ? 'error' : 'success'
          }`}
        >
          {message}
        </p>
      )}

      {loading ? (
        <p className="admin-cup-helper">{t('adminCup.loading')}</p>
      ) : !snapshot ? (
        <>
          <p className="admin-cup-helper">
            {t('adminCup.loadStateFailed')}
          </p>
          <button
            type="button"
            className="league-refresh-button"
            onClick={() => void loadPanel()}
          >
            {t('common.refresh')}
          </button>
        </>
      ) : cup ? (
        <>
          <p className="admin-cup-helper">
            {t('adminCup.playersAt', {
              count: cup.participant_count,
              when: formatCreatedAt(cup.created_at),
            })}
          </p>

          {confirming === 'recompute' ? (
            <div className="admin-notifications-confirm">
              <p>
                {t('adminCup.recomputeConfirm')}
              </p>
              <div className="admin-notifications-confirm-actions">
                <button
                  type="button"
                  className="admin-save-button"
                  disabled={isBusy}
                  onClick={() => void handleRecompute()}
                >
                  {busyAction === 'recompute'
                    ? t('adminCup.recomputing')
                    : t('common.confirm')}
                </button>
                <button
                  type="button"
                  className="admin-notifications-cancel"
                  disabled={isBusy}
                  onClick={() => setConfirming(null)}
                >
                  {t('common.cancel')}
                </button>
              </div>
            </div>
          ) : (
            <button
              type="button"
              className="admin-cup-recovery"
              disabled={isBusy}
              onClick={() => {
                setMessage('')
                setConfirming('recompute')
              }}
            >
              {t('adminCup.recompute')}
            </button>
          )}
          <p className="admin-cup-recovery-note">
            {t('adminCup.recomputeNote')}
          </p>
        </>
      ) : confirming === 'draw' ? (
        <div className="admin-notifications-confirm">
          <p>
            {t('adminCup.drawConfirm')}
          </p>
          <div className="admin-notifications-confirm-actions">
            <button
              type="button"
              className="admin-save-button"
              disabled={isBusy}
              onClick={() => void handleDraw()}
            >
              {busyAction === 'draw' ? t('adminCup.drawing') : t('common.confirm')}
            </button>
            <button
              type="button"
              className="admin-notifications-cancel"
              disabled={isBusy}
              onClick={() => setConfirming(null)}
            >
              {t('common.cancel')}
            </button>
          </div>
        </div>
      ) : (
        <>
          {helper && <p className="admin-cup-helper">{helper}</p>}
          <button
            type="button"
            className="admin-save-button"
            disabled={!canDraw || isBusy}
            onClick={() => {
              setMessage('')
              setConfirming('draw')
            }}
          >
            {t('adminCup.doDraw')}
          </button>
        </>
      )}
    </section>
  )
}
