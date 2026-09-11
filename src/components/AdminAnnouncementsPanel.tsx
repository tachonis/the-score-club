import { useCallback, useEffect, useState } from 'react'
import { dateLocale, t, type MessageKey } from '../i18n'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import {
  announcementBodyLimit,
  announcementCategories,
  announcementTitleLimit,
  deleteAnnouncement,
  isAnnouncementCategory,
  loadAdminAnnouncements,
  previewAnnouncementBody,
  saveAnnouncement,
  type Announcement,
  type AnnouncementCategory,
} from '../lib/announcements'
import { announcementPushDestination } from '../lib/pushDestination'
import { supabase } from '../lib/supabase'

type BroadcastResult = {
  attempted: number
  delivered: number
  gone: number
  failed: number
}

const categoryKeys: Record<AnnouncementCategory, MessageKey> = {
  general: 'announcements.categories.general',
  matchday: 'announcements.categories.matchday',
  cup: 'announcements.categories.cup',
  rules: 'announcements.categories.rules',
}

const pushTitleLimit = 80
const pushMessageLimit = 250

const emptyForm = {
  title: '',
  body: '',
  category: '' as AnnouncementCategory | '',
  isPublished: false,
}

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

  return error instanceof Error
    ? error.message
    : t('adminAnnouncements.unknownError')
}

const formatWhen = (value: string) =>
  new Intl.DateTimeFormat(dateLocale, {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(value))

export function AdminAnnouncementsPanel() {
  const [rows, setRows] = useState<Announcement[]>([])
  const [loading, setLoading] = useState(true)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [form, setForm] = useState(emptyForm)
  const [saving, setSaving] = useState(false)
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [pushingId, setPushingId] = useState<string | null>(null)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )

  const trimmedTitle = form.title.trim()
  const trimmedBody = form.body.trim()
  const canSave = trimmedTitle !== '' && trimmedBody !== ''

  const loadRows = useCallback(async () => {
    setLoading(true)

    try {
      const nextRows = await loadAdminAnnouncements()
      setRows(nextRows)
      setMessage('')
    } catch (error) {
      setMessageType('error')
      setMessage(
        t('adminAnnouncements.loadFailed', {
          detail:
            error instanceof Error
              ? error.message
              : t('adminAnnouncements.unknownError'),
        }),
      )
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadRows()
  }, [loadRows])

  const resetForm = () => {
    setEditingId(null)
    setForm(emptyForm)
  }

  const handleEdit = (row: Announcement) => {
    setEditingId(row.id)
    setForm({
      title: row.title,
      body: row.body,
      category: row.category ?? '',
      isPublished: row.is_published,
    })
    setMessage('')
  }

  const handleSave = async () => {
    if (!canSave || saving) return

    setSaving(true)
    setMessage('')

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      await saveAnnouncement({
        id: editingId ?? undefined,
        title: trimmedTitle,
        body: trimmedBody,
        category: form.category,
        isPublished: form.isPublished,
        createdBy: user?.id ?? null,
      })
      resetForm()
      await loadRows()
      setMessageType('success')
      setMessage(
        form.isPublished
          ? t('adminAnnouncements.savedPublished')
          : t('adminAnnouncements.savedDraft'),
      )
    } catch (error) {
      setMessageType('error')
      setMessage(
        t('adminAnnouncements.saveFailed', {
          detail:
            error instanceof Error
              ? error.message
              : t('adminAnnouncements.unknownError'),
        }),
      )
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async (id: string) => {
    if (deletingId) return
    if (!window.confirm(t('adminAnnouncements.confirmDelete'))) return

    setDeletingId(id)
    setMessage('')

    try {
      await deleteAnnouncement(id)
      if (editingId === id) {
        resetForm()
      }
      await loadRows()
      setMessageType('success')
      setMessage(t('adminAnnouncements.deleted'))
    } catch (error) {
      setMessageType('error')
      setMessage(
        t('adminAnnouncements.deleteFailed', {
          detail:
            error instanceof Error
              ? error.message
              : t('adminAnnouncements.unknownError'),
        }),
      )
    } finally {
      setDeletingId(null)
    }
  }

  const handleSendPush = async (row: Announcement) => {
    if (!row.is_published || pushingId) return
    if (!window.confirm(t('adminAnnouncements.confirmPush'))) return

    setPushingId(row.id)
    setMessage('')

    const { data, error } = await supabase.functions.invoke(
      'send-broadcast-push',
      {
        body: {
          title: row.title.slice(0, pushTitleLimit),
          message: previewAnnouncementBody(row.body).slice(0, pushMessageLimit),
          destination: announcementPushDestination(row.id),
        },
      },
    )

    if (error) {
      setMessageType('error')
      setMessage(
        t('adminAnnouncements.pushFailed', {
          detail: await readErrorDetail(error),
        }),
      )
      setPushingId(null)
      return
    }

    const result = data as BroadcastResult
    setMessageType('success')
    setMessage(
      t('adminAnnouncements.pushSent', { count: result.delivered }),
    )
    setPushingId(null)
  }

  return (
    <section className="admin-announcements-panel">
      <div className="admin-outcomes-heading">
        <div>
          <p className="dashboard-eyebrow">
            {formatGreekAllCaps(t('adminAnnouncements.kicker'))}
          </p>
          <h2>{t('adminAnnouncements.heading')}</h2>
          <p>{t('adminAnnouncements.intro')}</p>
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
          <span>{t('adminAnnouncements.title')}</span>
          <input
            type="text"
            value={form.title}
            maxLength={announcementTitleLimit}
            disabled={saving}
            onChange={(event) =>
              setForm((current) => ({ ...current, title: event.target.value }))
            }
          />
          <small>
            {trimmedTitle.length}/{announcementTitleLimit}
          </small>
        </label>

        <label>
          <span>{t('adminAnnouncements.body')}</span>
          <textarea
            rows={7}
            value={form.body}
            maxLength={announcementBodyLimit}
            disabled={saving}
            onChange={(event) =>
              setForm((current) => ({ ...current, body: event.target.value }))
            }
          />
          <small>
            {trimmedBody.length}/{announcementBodyLimit}
          </small>
        </label>

        <label>
          <span>{t('adminAnnouncements.category')}</span>
          <select
            value={form.category}
            disabled={saving}
            onChange={(event) =>
              setForm((current) => ({
                ...current,
                category: isAnnouncementCategory(event.target.value)
                  ? event.target.value
                  : '',
              }))
            }
          >
            <option value="">{t('adminAnnouncements.categoryNone')}</option>
            {announcementCategories.map((value) => (
              <option key={value} value={value}>
                {t(categoryKeys[value])}
              </option>
            ))}
          </select>
        </label>

        <label className="admin-announcements-publish">
          <input
            type="checkbox"
            checked={form.isPublished}
            disabled={saving}
            onChange={(event) =>
              setForm((current) => ({
                ...current,
                isPublished: event.target.checked,
              }))
            }
          />
          <span>{t('adminAnnouncements.publish')}</span>
        </label>
      </div>

      <div className="admin-announcements-form-actions">
        <button
          type="button"
          className="admin-save-button"
          disabled={!canSave || saving}
          onClick={() => void handleSave()}
        >
          {saving
            ? t('common.saving')
            : editingId
              ? t('adminAnnouncements.save')
              : t('adminAnnouncements.create')}
        </button>
        {editingId ? (
          <button
            type="button"
            className="admin-notifications-cancel"
            disabled={saving}
            onClick={resetForm}
          >
            {t('common.cancel')}
          </button>
        ) : null}
      </div>

      {loading ? (
        <p>{t('adminAnnouncements.loading')}</p>
      ) : rows.length === 0 ? (
        <p>{t('adminAnnouncements.empty')}</p>
      ) : (
        <div className="admin-announcements-list">
          {rows.map((row) => {
            const busy = saving || deletingId !== null || pushingId !== null

            return (
              <article
                className={`admin-announcement-card${
                  row.is_published ? ' published' : ' draft'
                }`}
                key={row.id}
              >
                <div className="admin-announcement-meta">
                  <span
                    className={`admin-announcement-status ${
                      row.is_published ? 'published' : 'draft'
                    }`}
                  >
                    {row.is_published
                      ? t('adminAnnouncements.published')
                      : t('adminAnnouncements.draft')}
                  </span>
                  {row.category ? (
                    <span>
                      {isAnnouncementCategory(row.category)
                        ? t(categoryKeys[row.category])
                        : row.category}
                    </span>
                  ) : null}
                  <time dateTime={row.published_at ?? row.created_at}>
                    {formatWhen(row.published_at ?? row.created_at)}
                  </time>
                </div>
                <strong>{row.title}</strong>
                <p>{previewAnnouncementBody(row.body)}</p>
                <div className="admin-announcement-actions">
                  <button
                    type="button"
                    className="admin-notifications-test-button"
                    disabled={busy}
                    onClick={() => handleEdit(row)}
                  >
                    {t('common.edit')}
                  </button>
                  {row.is_published ? (
                    <button
                      type="button"
                      className="admin-save-button"
                      disabled={busy}
                      onClick={() => void handleSendPush(row)}
                    >
                      {pushingId === row.id
                        ? t('adminAnnouncements.sendingPush')
                        : t('adminAnnouncements.sendPush')}
                    </button>
                  ) : null}
                  <button
                    type="button"
                    className="admin-notifications-cancel"
                    disabled={busy}
                    onClick={() => void handleDelete(row.id)}
                  >
                    {deletingId === row.id
                      ? t('adminAnnouncements.deleting')
                      : t('adminAnnouncements.delete')}
                  </button>
                </div>
              </article>
            )
          })}
        </div>
      )}
    </section>
  )
}
