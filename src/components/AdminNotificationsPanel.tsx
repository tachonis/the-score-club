import { useState } from 'react'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { supabase } from '../lib/supabase'
import type { PushDestination } from '../lib/push'

type BroadcastResult = {
  attempted: number
  delivered: number
  gone: number
  failed: number
  self_only?: boolean
}

const destinationOptions: Array<{
  value: PushDestination
  label: string
}> = [
  { value: 'predictions', label: 'Αγώνες & Προβλέψεις' },
  { value: 'home', label: 'Αρχική' },
  { value: 'standings', label: 'Βαθμολογία' },
  { value: 'league-phase', label: 'League Phase' },
  { value: 'rules', label: 'Κανόνες' },
]

const titleLimit = 80
const messageLimit = 250
const testDestination: PushDestination = 'predictions'

const readErrorDetail = async (error: unknown) => {
  const context = (error as { context?: unknown }).context

  if (context instanceof Response) {
    try {
      const payload = (await context.json()) as { error?: string }

      if (typeof payload.error === 'string' && payload.error !== '') {
        return payload.error
      }
    } catch {
      // Fall through to the generic client message.
    }
  }

  return error instanceof Error ? error.message : 'Άγνωστο σφάλμα'
}

const describeResult = (result: BroadcastResult) => {
  const parts = [`Στάλθηκε σε ${result.delivered} συσκευές.`]

  if (result.gone > 0) {
    parts.push(
      `${result.gone} ${
        result.gone === 1 ? 'παλιά συνδρομή αφαιρέθηκε' : 'παλιές συνδρομές αφαιρέθηκαν'
      }.`,
    )
  }

  if (result.failed > 0) {
    parts.push(
      `${result.failed} ${result.failed === 1 ? 'απέτυχε' : 'απέτυχαν'}.`,
    )
  }

  if (result.attempted === 0) {
    return 'Καμία συσκευή δεν έχει ενεργοποιήσει ειδοποιήσεις.'
  }

  return parts.join(' ')
}

const describeTestResult = (result: BroadcastResult) => {
  if (result.attempted === 0) {
    return 'Δεν υπάρχει ενεργή συνδρομή στον λογαριασμό σου. Ενεργοποίησε τις ειδοποιήσεις στην Αρχική και δοκίμασε ξανά.'
  }

  if (result.delivered === 0) {
    return 'Η δοκιμαστική ειδοποίηση δεν έφτασε στις συσκευές σου. Δοκίμασε ξανά.'
  }

  return 'Η δοκιμαστική ειδοποίηση στάλθηκε στις συσκευές σου.'
}

export function AdminNotificationsPanel() {
  const [title, setTitle] = useState('The Score Club')
  const [body, setBody] = useState('')
  const [destination, setDestination] =
    useState<PushDestination>('predictions')
  const [confirming, setConfirming] = useState(false)
  const [sendingKind, setSendingKind] = useState<'broadcast' | 'test' | null>(
    null,
  )
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )

  const trimmedTitle = title.trim()
  const trimmedBody = body.trim()
  const canSend = trimmedTitle !== '' && trimmedBody !== ''
  const sending = sendingKind !== null

  const handleSend = async () => {
    setSendingKind('broadcast')
    setMessage('')

    const { data, error } = await supabase.functions.invoke(
      'send-broadcast-push',
      {
        body: {
          title: trimmedTitle,
          message: trimmedBody,
          destination,
        },
      },
    )

    if (error) {
      setMessageType('error')
      setMessage(
        `Δεν στάλθηκε η ειδοποίηση: ${await readErrorDetail(error)}`,
      )
      setSendingKind(null)
      setConfirming(false)
      return
    }

    setMessageType('success')
    setMessage(describeResult(data as BroadcastResult))
    setBody('')
    setSendingKind(null)
    setConfirming(false)
  }

  const handleTestSend = async () => {
    setSendingKind('test')
    setMessage('')

    const { data, error } = await supabase.functions.invoke(
      'send-broadcast-push',
      {
        body: {
          title: trimmedTitle || 'The Score Club',
          message: trimmedBody || 'Δοκιμαστική ειδοποίηση.',
          destination: testDestination,
          self_only: true,
        },
      },
    )

    if (error) {
      setMessageType('error')
      setMessage('Δεν στάλθηκε η δοκιμαστική ειδοποίηση. Δοκίμασε ξανά.')
      setSendingKind(null)
      return
    }

    const result = data as BroadcastResult
    const failed = result.attempted === 0 || result.delivered === 0

    setMessageType(failed ? 'error' : 'success')
    setMessage(describeTestResult(result))
    setSendingKind(null)
  }

  return (
    <section className="admin-notifications-panel">
      <div className="admin-outcomes-heading">
        <div>
          <p className="dashboard-eyebrow">
            {formatGreekAllCaps('Admin-only αποστολή')}
          </p>
          <h2>Ειδοποιήσεις παικτών</h2>
          <p>
            Η ειδοποίηση φτάνει σε κάθε συσκευή που έχει ενεργοποιήσει
            ειδοποιήσεις, ακόμη και όταν η εφαρμογή είναι κλειστή.
          </p>
        </div>
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

      <div className="admin-notifications-form">
        <label>
          <span>Τίτλος</span>
          <input
            type="text"
            value={title}
            maxLength={titleLimit}
            disabled={sending}
            onChange={(event) => {
              setConfirming(false)
              setTitle(event.target.value)
            }}
          />
          <small>
            {trimmedTitle.length}/{titleLimit}
          </small>
        </label>

        <label>
          <span>Μήνυμα</span>
          <textarea
            rows={3}
            value={body}
            maxLength={messageLimit}
            disabled={sending}
            placeholder="Μην ξεχάσετε τις προβλέψεις σας."
            onChange={(event) => {
              setConfirming(false)
              setBody(event.target.value)
            }}
          />
          <small>
            {trimmedBody.length}/{messageLimit}
          </small>
        </label>

        <label>
          <span>Προορισμός</span>
          <select
            value={destination}
            disabled={sending}
            onChange={(event) => {
              setConfirming(false)
              setDestination(event.target.value as PushDestination)
            }}
          >
            {destinationOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      {confirming ? (
        <div className="admin-notifications-confirm">
          <p>
            Η ειδοποίηση θα σταλεί σε όλες τις συσκευές που έχουν
            ενεργοποιήσει ειδοποιήσεις. Να συνεχίσω;
          </p>
          <div className="admin-notifications-confirm-actions">
            <button
              type="button"
              className="admin-save-button"
              disabled={sending}
              onClick={() => void handleSend()}
            >
              {sendingKind === 'broadcast'
                ? 'Αποστολή...'
                : 'Επιβεβαίωση αποστολής'}
            </button>
            <button
              type="button"
              className="admin-notifications-cancel"
              disabled={sending}
              onClick={() => setConfirming(false)}
            >
              Ακύρωση
            </button>
          </div>
        </div>
      ) : (
        <button
          type="button"
          className="admin-save-button"
          disabled={!canSend || sending}
          onClick={() => {
            setMessage('')
            setConfirming(true)
          }}
        >
          Αποστολή ειδοποίησης
        </button>
      )}

      <div className="admin-notifications-test">
        <button
          type="button"
          className="admin-notifications-test-button"
          disabled={sending || confirming}
          onClick={() => void handleTestSend()}
        >
          {sendingKind === 'test'
            ? 'Αποστολή δοκιμής...'
            : 'Αποστολή δοκιμαστικής ειδοποίησης σε εμένα'}
        </button>
        <p className="admin-notifications-test-note">
          Στέλνεται μόνο στις δικές σου συσκευές. Δεν ειδοποιεί τους παίκτες.
        </p>
      </div>
    </section>
  )
}
