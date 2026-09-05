import { useCallback, useEffect, useState } from 'react'
import { dateLocale, t, type MessageKey } from '../i18n'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import {
  isFeedbackCategory,
  loadFeedbackInbox,
  setFeedbackStatus,
  type FeedbackCategory,
  type FeedbackInboxRow,
  type FeedbackStatus,
} from '../lib/feedback'

const categoryKeys: Record<FeedbackCategory, MessageKey> = {
  bug: 'contact.categories.bug',
  account: 'contact.categories.account',
  suggestion: 'contact.categories.suggestion',
  other: 'contact.categories.other',
}

const statusLabel = (status: FeedbackStatus) =>
  status === 'new'
    ? t('adminFeedback.statusNew')
    : status === 'read'
      ? t('adminFeedback.statusRead')
      : t('adminFeedback.statusResolved')

export function AdminFeedbackPanel() {
  const [rows, setRows] = useState<FeedbackInboxRow[]>([])
  const [loading, setLoading] = useState(true)
  const [updatingId, setUpdatingId] = useState<string | null>(null)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )

  const loadInbox = useCallback(async () => {
    setLoading(true)

    try {
      const nextRows = await loadFeedbackInbox()
      setRows(nextRows)
      setMessage('')
    } catch (error) {
      setMessageType('error')
      setMessage(
        t('adminFeedback.loadFailed', {
          detail:
            error instanceof Error
              ? error.message
              : t('adminFeedback.unknownError'),
        }),
      )
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadInbox()
  }, [loadInbox])

  const newCount = rows.filter((row) => row.status === 'new').length

  const handleStatus = async (id: string, status: FeedbackStatus) => {
    setUpdatingId(id)
    setMessage('')

    try {
      await setFeedbackStatus(id, status)
      await loadInbox()
    } catch (error) {
      setMessageType('error')
      setMessage(
        t('adminFeedback.updateFailed', {
          detail:
            error instanceof Error
              ? error.message
              : t('adminFeedback.unknownError'),
        }),
      )
    } finally {
      setUpdatingId(null)
    }
  }

  const formatSubmittedAt = (value: string) =>
    new Intl.DateTimeFormat(dateLocale, {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(value))

  return (
    <section className="admin-feedback-panel">
      <div className="admin-outcomes-heading">
        <div>
          <p className="dashboard-eyebrow">
            {formatGreekAllCaps(t('adminFeedback.kicker'))}
          </p>
          <h2>
            {newCount > 0
              ? t('adminFeedback.headingWithNew', { count: newCount })
              : t('adminFeedback.heading')}
          </h2>
          <p>{t('adminFeedback.intro')}</p>
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

      {loading ? (
        <p>{t('adminFeedback.loading')}</p>
      ) : rows.length === 0 ? (
        <p>{t('adminFeedback.empty')}</p>
      ) : (
        <div className="admin-feedback-list">
          {rows.map((row) => {
            const busy = updatingId === row.id

            return (
              <article
                className={`admin-feedback-card status-${row.status}`}
                key={row.id}
              >
                <div className="admin-feedback-meta">
                  <span className={`admin-feedback-status ${row.status}`}>
                    {statusLabel(row.status)}
                  </span>
                  <span>
                    {isFeedbackCategory(row.category)
                      ? t(categoryKeys[row.category])
                      : row.category}
                  </span>
                  <strong>{row.username}</strong>
                  <span className="admin-feedback-email">
                    {row.email?.trim() || t('common.dash')}
                  </span>
                  <time dateTime={row.created_at}>
                    {formatSubmittedAt(row.created_at)}
                  </time>
                </div>
                <p className="admin-feedback-body">{row.message}</p>
                {row.status !== 'resolved' && (
                  <div className="admin-feedback-actions">
                    {row.status === 'new' && (
                      <button
                        type="button"
                        className="admin-notifications-test-button"
                        disabled={busy || updatingId !== null}
                        onClick={() => void handleStatus(row.id, 'read')}
                      >
                        {t('adminFeedback.markRead')}
                      </button>
                    )}
                    <button
                      type="button"
                      className="admin-save-button"
                      disabled={busy || updatingId !== null}
                      onClick={() => void handleStatus(row.id, 'resolved')}
                    >
                      {t('adminFeedback.markResolved')}
                    </button>
                  </div>
                )}
              </article>
            )
          })}
        </div>
      )}
    </section>
  )
}
