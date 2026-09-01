import { useState } from 'react'
import { selectPlural, t } from '../i18n'
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
  { value: 'predictions', label: t('nav.matches') },
  { value: 'home', label: t('nav.home') },
  { value: 'standings', label: t('nav.standings') },
  { value: 'league-phase', label: t('nav.leaguePhase') },
  { value: 'rules', label: t('nav.rules') },
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

  return error instanceof Error ? error.message : t('adminPush.unknownError')
}

const describeResult = (result: BroadcastResult) => {
  const parts = [t('adminPush.delivered', { count: result.delivered })]

  if (result.gone > 0) {
    parts.push(
      t(selectPlural(result.gone, 'adminPush.goneOne', 'adminPush.goneMany'), {
        count: result.gone,
      }),
    )
  }

  if (result.failed > 0) {
    parts.push(
      t(
        selectPlural(result.failed, 'adminPush.failedOne', 'adminPush.failedMany'),
        { count: result.failed },
      ),
    )
  }

  if (result.attempted === 0) {
    return t('adminPush.noDevices')
  }

  return parts.join(' ')
}

const describeTestResult = (result: BroadcastResult) => {
  if (result.attempted === 0) {
    return t('adminPush.testNoSub')
  }

  if (result.delivered === 0) {
    return t('adminPush.testNotDelivered')
  }

  return t('adminPush.testSent')
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
        t('adminPush.sendFailed', {
          detail: await readErrorDetail(error),
        }),
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
          message: trimmedBody || t('adminPush.testDefaultBody'),
          destination: testDestination,
          self_only: true,
        },
      },
    )

    if (error) {
      setMessageType('error')
      setMessage(t('adminPush.testFailed'))
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
            {formatGreekAllCaps(t('adminPush.kicker'))}
          </p>
          <h2>{t('adminPush.heading')}</h2>
          <p>
            {t('adminPush.intro')}
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
          <span>{t('adminPush.title')}</span>
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
          <span>{t('adminPush.message')}</span>
          <textarea
            rows={3}
            value={body}
            maxLength={messageLimit}
            disabled={sending}
            placeholder={t('adminPush.placeholder')}
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
          <span>{t('adminPush.destination')}</span>
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
            {t('adminPush.confirm')}
          </p>
          <div className="admin-notifications-confirm-actions">
            <button
              type="button"
              className="admin-save-button"
              disabled={sending}
              onClick={() => void handleSend()}
            >
              {sendingKind === 'broadcast'
                ? t('adminPush.sending')
                : t('adminPush.confirmSend')}
            </button>
            <button
              type="button"
              className="admin-notifications-cancel"
              disabled={sending}
              onClick={() => setConfirming(false)}
            >
              {t('common.cancel')}
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
          {t('adminPush.send')}
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
            ? t('adminPush.sendingTest')
            : t('adminPush.sendTest')}
        </button>
        <p className="admin-notifications-test-note">
          {t('adminPush.testNote')}
        </p>
      </div>
    </section>
  )
}
