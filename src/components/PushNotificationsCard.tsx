import { useEffect, useState } from 'react'
import {
  disablePush,
  enablePush,
  getPushStatus,
  syncPushSubscription,
  type PushStatus,
} from '../lib/push'

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
  cta: 'Ενεργοποίησε ειδοποιήσεις για να λαμβάνεις υπενθυμίσεις πριν από τις αγωνιστικές.',
  subscribed: 'Ειδοποιήσεις ενεργές',
  idle: 'Ειδοποιήσεις ανενεργές',
  denied: 'Οι ειδοποιήσεις είναι αποκλεισμένες',
  'ios-install': '',
  unsupported: 'Η συσκευή ή ο browser δεν υποστηρίζει ειδοποιήσεις',
}

const notes: Record<PushUiState, string> = {
  loading: '',
  cta: '',
  subscribed: 'σε αυτή τη συσκευή',
  idle: 'σε αυτή τη συσκευή',
  denied: 'Επίτρεψέ τες ξανά από τις ρυθμίσεις του browser ή της συσκευής.',
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
          ? `Δεν ενεργοποιήθηκαν οι ειδοποιήσεις: ${enableError.message}`
          : 'Δεν ενεργοποιήθηκαν οι ειδοποιήσεις.',
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
          ? `Δεν απενεργοποιήθηκαν οι ειδοποιήσεις: ${disableError.message}`
          : 'Δεν απενεργοποιήθηκαν οι ειδοποιήσεις.',
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
          className: 'push-row-action',
          label: busy ? 'Απενεργοποίηση...' : 'Απενεργοποίηση',
          onClick: handleDisable,
        }
      : uiState === 'idle'
        ? {
            className: 'push-row-action',
            label: busy ? 'Ενεργοποίηση...' : 'Ενεργοποίηση',
            onClick: handleEnable,
          }
        : uiState === 'cta'
          ? {
              className: 'push-cta-button',
              label: busy ? 'Ενεργοποίηση...' : 'Ενεργοποίηση ειδοποιήσεων',
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
            <summary>
              Για ειδοποιήσεις στο iPhone, πρόσθεσε το The Score Club στην
              Αρχική οθόνη
            </summary>
            <ol className="push-row-steps">
              <li>Άνοιξε το The Score Club στο Safari.</li>
              <li>
                Πάτησε Κοινή χρήση και μετά «Προσθήκη στην οθόνη Αφετηρίας».
              </li>
              <li>Άνοιξε το εικονίδιο The Score Club από την οθόνη σου.</li>
              <li>Ενεργοποίησε εκεί τις ειδοποιήσεις.</li>
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
