import { useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import {
  feedbackCategories,
  feedbackMessageLimit,
  isFeedbackCategory,
  submitFeedback,
  type FeedbackCategory,
} from '../lib/feedback'
import { t, type MessageKey } from '../i18n'

const categoryKeys: Record<FeedbackCategory, MessageKey> = {
  bug: 'contact.categories.bug',
  account: 'contact.categories.account',
  suggestion: 'contact.categories.suggestion',
  other: 'contact.categories.other',
}

type ContactPageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

export function ContactPage({
  username,
  role,
  onNavigate,
  onLogout,
}: ContactPageProps) {
  const [category, setCategory] = useState('')
  const [message, setMessage] = useState('')
  const [sending, setSending] = useState(false)
  const [flash, setFlash] = useState('')
  const [flashType, setFlashType] = useState<'success' | 'error'>('success')

  const trimmedMessage = message.trim()
  const canSend =
    isFeedbackCategory(category) &&
    trimmedMessage.length > 0 &&
    trimmedMessage.length <= feedbackMessageLimit

  const handleSubmit = async () => {
    if (!canSend || sending) return

    setSending(true)
    setFlash('')

    try {
      await submitFeedback(category as FeedbackCategory, trimmedMessage)
      setCategory('')
      setMessage('')
      setFlashType('success')
      setFlash(t('contact.success'))
    } catch (error) {
      setFlashType('error')
      setFlash(
        t('contact.failedDetail', {
          detail:
            error instanceof Error ? error.message : t('contact.unknownError'),
        }),
      )
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="contact"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="contact-page-main">
        <section className="contact-page-intro">
          <p className="dashboard-eyebrow">
            {formatGreekAllCaps(t('contact.kicker'))}
          </p>
          <h1>{t('contact.heading')}</h1>
          <p>{t('contact.intro')}</p>
        </section>

        <section className="contact-page-card">
          {flash && (
            <p
              className={`auth-message ${
                flashType === 'error' ? 'error' : 'success'
              }`}
            >
              {flash}
            </p>
          )}

          <form
            className="contact-form"
            onSubmit={(event) => {
              event.preventDefault()
              void handleSubmit()
            }}
          >
            <label>
              <span>{t('contact.category')}</span>
              <select
                value={category}
                disabled={sending}
                required
                onChange={(event) => {
                  setFlash('')
                  setCategory(event.target.value)
                }}
              >
                <option value="">{t('contact.chooseCategory')}</option>
                {feedbackCategories.map((value) => (
                  <option key={value} value={value}>
                    {t(categoryKeys[value])}
                  </option>
                ))}
              </select>
            </label>

            <label>
              <span>{t('contact.message')}</span>
              <textarea
                rows={7}
                value={message}
                maxLength={feedbackMessageLimit}
                disabled={sending}
                required
                placeholder={t('contact.placeholder')}
                onChange={(event) => {
                  setFlash('')
                  setMessage(event.target.value)
                }}
              />
              <small>
                {trimmedMessage.length}/{feedbackMessageLimit}
              </small>
            </label>

            <button
              type="submit"
              className="admin-save-button"
              disabled={!canSend || sending}
            >
              {sending ? t('contact.sending') : t('contact.send')}
            </button>
          </form>
        </section>
      </main>
    </div>
  )
}
