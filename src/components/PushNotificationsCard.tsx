import { useEffect, useState } from 'react'
import {
  disablePush,
  enablePush,
  getPushStatus,
  syncPushSubscription,
  type PushStatus,
} from '../lib/push'

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

  if (!status) return null

  const isSubscribed = status.availability === 'ready' && status.subscribed

  return (
    <section
      className={`push-card ${isSubscribed ? 'active' : ''}`}
      aria-label="Ειδοποιήσεις"
    >
      <div className="push-card-body">
        <p className="dashboard-eyebrow">Ειδοποιήσεις</p>

        {status.availability === 'unsupported' && (
          <p className="push-card-text">
            Η συσκευή ή ο browser δεν υποστηρίζει ειδοποιήσεις.
          </p>
        )}

        {status.availability === 'ios-needs-install' && (
          <>
            <p className="push-card-text">
              Στο iPhone και στο iPad οι ειδοποιήσεις δουλεύουν μόνο από την
              εγκατεστημένη εφαρμογή.
            </p>
            <ol className="push-card-steps">
              <li>Άνοιξε το The Score Club στο Safari.</li>
              <li>
                Πάτησε Κοινή χρήση και μετά «Προσθήκη στην οθόνη Αφετηρίας».
              </li>
              <li>Άνοιξε το εικονίδιο The Score Club από την οθόνη σου.</li>
              <li>Ενεργοποίησε εκεί τις ειδοποιήσεις.</li>
            </ol>
          </>
        )}

        {status.availability === 'ready' && status.permission === 'denied' && (
          <p className="push-card-text">
            Οι ειδοποιήσεις είναι αποκλεισμένες. Επίτρεψέ τες ξανά από τις
            ρυθμίσεις του browser ή της συσκευής και επέστρεψε σε αυτή τη
            σελίδα.
          </p>
        )}

        {status.availability === 'ready' &&
          status.permission !== 'denied' &&
          (isSubscribed ? (
            <p className="push-card-text">
              Οι ειδοποιήσεις είναι ενεργές σε αυτή τη συσκευή.
            </p>
          ) : (
            <p className="push-card-text">
              Ενεργοποίησε ειδοποιήσεις για να λαμβάνεις υπενθυμίσεις πριν από
              τις αγωνιστικές.
            </p>
          ))}

        {error && <p className="auth-message error">{error}</p>}
      </div>

      {status.availability === 'ready' && status.permission !== 'denied' && (
        <div className="push-card-actions">
          {isSubscribed ? (
            <button
              type="button"
              className="push-card-button secondary"
              disabled={busy}
              onClick={() => void handleDisable()}
            >
              {busy ? 'Απενεργοποίηση...' : 'Απενεργοποίηση'}
            </button>
          ) : (
            <button
              type="button"
              className="push-card-button"
              disabled={busy}
              onClick={() => void handleEnable()}
            >
              {busy
                ? 'Ενεργοποίηση...'
                : status.permission === 'granted'
                  ? 'Ενεργοποίηση σε αυτή τη συσκευή'
                  : 'Ενεργοποίηση ειδοποιήσεων'}
            </button>
          )}
        </div>
      )}
    </section>
  )
}
