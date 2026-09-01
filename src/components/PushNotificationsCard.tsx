import { useEffect, useState } from 'react'
import {
  disablePush,
  enablePush,
  getPushStatus,
  syncPushSubscription,
  type PushStatus,
} from '../lib/push'
import { t } from '../i18n'

type PushUiState =
  | 'loading'
  | 'cta'
  | 'subscribed'
  | 'idle'
  | 'denied'
  | 'ios-install'
  | 'unsupported'

const readUiState = (status: PushStatus | null): PushUiState => {
  if (!status) return 'loading'
  if (status.availability === 'unsupported') return 'unsupported'
  if (status.availability === 'ios-needs-install') return 'ios-install'
  if (status.permission === 'denied') return 'denied'
  if (status.subscribed) return 'subscribed'

  return status.permission === 'granted' ? 'idle' : 'cta'
}

const variantClass: Record<PushUiState, string> = {
  loading: 'push-slot--loading',
  cta: 'push-slot--cta',
  subscribed: 'push-slot--on',
  idle: 'push-slot--off',
  denied: 'push-slot--muted',
  'ios-install': 'push-slot--ios',
  unsupported: 'push-slot--muted',
}

const labels: Record<PushUiState, string> = {
  loading: '',
  cta: t('push.cta'),
  subscribed: t('push.on'),
  idle: t('push.off'),
  denied: t('push.denied'),
  'ios-install': '',
  unsupported: t('push.unsupported'),
}

const notes: Record<PushUiState, string> = {
  loading: '',
  cta: '',
  subscribed: t('push.onThisDevice'),
  idle: t('push.onThisDevice'),
  denied: t('push.deniedHint'),
  'ios-install': '',
  unsupported: '',
}

export function PushNotificationsCard() {
  const [status, setStatus] = useState<PushStatus | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true

    const loadStatus = async () => {
      let nextStatus: PushStatus

      try {
        nextStatus = await getPushStatus()
      } catch {
        nextStatus = {
          availability: 'unsupported',
          permission: 'default',
          subscribed: false,
        }
      }

      if (!active) return

      setStatus(nextStatus)

      if (!nextStatus.subscribed) return

      try {
        await syncPushSubscription()
      } catch {
        // A failed re-bind must never block the dashboard.
      }
    }

    void loadStatus()

    return () => {
      active = false
    }
  }, [])

  const handleEnable = async () => {
    if (busy) return

    setBusy(true)
    setError('')

    try {
      setStatus(await enablePush())
    } catch (enableError) {
      setError(
        enableError instanceof Error
          ? t('push.enableFailedDetail', { detail: enableError.message })
          : t('push.enableFailed'),
      )
    }

    setBusy(false)
  }

  const handleDisable = async () => {
    if (busy) return

    setBusy(true)
    setError('')

    try {
      setStatus(await disablePush())
    } catch (disableError) {
      setError(
        disableError instanceof Error
          ? t('push.disableFailedDetail', { detail: disableError.message })
          : t('push.disableFailed'),
      )
    }

    setBusy(false)
  }

  const uiState = readUiState(status)
  const label = labels[uiState]
  const note = notes[uiState]

  const action =
    uiState === 'subscribed'
      ? {
          className: 'push-row-action push-row-action--quiet',
          label: busy ? t('push.disabling') : t('push.disable'),
          onClick: handleDisable,
        }
      : uiState === 'idle'
        ? {
            className: 'push-row-action',
            label: busy ? t('push.enabling') : t('push.enable'),
            onClick: handleEnable,
          }
        : uiState === 'cta'
          ? {
              className: 'push-cta-button',
              label: busy ? t('push.enabling') : t('push.enableCta'),
              onClick: handleEnable,
            }
          : null

  // Every state renders the same skeleton so React keeps the live region and
  // the action button mounted across transitions. That keeps status changes
  // announced and leaves keyboard focus on the button the player just used.
  return (
    <section className={`push-slot ${variantClass[uiState]}`}>
      <span className="push-row-icon" aria-hidden="true">
        {uiState === 'subscribed' ? '🔔' : '🔕'}
      </span>

      <div className="push-row-main">
        <p className="push-row-text" role="status" aria-live="polite">
          {label !== '' && <strong className="push-row-label">{label}</strong>}
          {note !== '' && <small className="push-row-note">{note}</small>}
        </p>

        {uiState === 'ios-install' && (
          <details className="push-row-disclosure">
            <summary>{t('push.iosSummary')}</summary>
            <ol className="push-row-steps">
              <li>{t('push.iosStep1')}</li>
              <li>{t('push.iosStep2')}</li>
              <li>{t('push.iosStep3')}</li>
              <li>{t('push.iosStep4')}</li>
            </ol>
          </details>
        )}

        {error !== '' && <p className="push-row-error">{error}</p>}
      </div>

      {action && (
        <div className="push-row-actions">
          <button
            type="button"
            className={action.className}
            aria-busy={busy}
            aria-disabled={busy}
            onClick={() => void action.onClick()}
          >
            {action.label}
          </button>
        </div>
      )}
    </section>
  )
}
