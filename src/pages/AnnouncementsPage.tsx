import { useEffect, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { LoadingMark } from '../components/BrandAssets'
import { dateLocale, t, type MessageKey } from '../i18n'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import {
  isAnnouncementCategory,
  loadAnnouncementById,
  loadPublishedAnnouncements,
  markAnnouncementRead,
  previewAnnouncementBody,
  type AnnouncementCategory,
  type AnnouncementListItem,
} from '../lib/announcements'

type AnnouncementsPageProps = {
  username: string
  role: 'player' | 'admin'
  selectedId: string | null
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
  onOpen: (id: string) => void
  onBackToList: () => void
}

const categoryKeys: Record<AnnouncementCategory, MessageKey> = {
  general: 'announcements.categories.general',
  matchday: 'announcements.categories.matchday',
  cup: 'announcements.categories.cup',
  rules: 'announcements.categories.rules',
}

const formatPublishedAt = (value: string) =>
  new Intl.DateTimeFormat(dateLocale, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(new Date(value))

function CategoryMark({ category }: { category: string | null }) {
  const label = isAnnouncementCategory(category ?? '')
    ? t(categoryKeys[category as AnnouncementCategory])
    : t('announcements.categories.general')

  return (
    <span className="announcement-category" title={label} aria-label={label}>
      {category === 'matchday' ? (
        '⚽'
      ) : category === 'cup' ? (
        '🏆'
      ) : category === 'rules' ? (
        '📋'
      ) : (
        '📣'
      )}
    </span>
  )
}

export function AnnouncementsPage({
  username,
  role,
  selectedId,
  onNavigate,
  onLogout,
  onOpen,
  onBackToList,
}: AnnouncementsPageProps) {
  const [items, setItems] = useState<AnnouncementListItem[]>([])
  const [detail, setDetail] = useState<AnnouncementListItem | null>(null)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')

  useEffect(() => {
    if (selectedId) {
      return
    }

    let active = true

    const loadList = async () => {
      setLoading(true)
      setMessage('')

      try {
        const nextItems = await loadPublishedAnnouncements()

        if (active) {
          setItems(nextItems)
        }
      } catch (error) {
        if (active) {
          setMessage(
            t('announcements.loadFailed', {
              detail:
                error instanceof Error
                  ? error.message
                  : t('announcements.unknownError'),
            }),
          )
        }
      } finally {
        if (active) {
          setLoading(false)
        }
      }
    }

    void loadList()

    return () => {
      active = false
    }
  }, [selectedId])

  useEffect(() => {
    if (!selectedId) {
      setDetail(null)
      return
    }

    let active = true

    const loadDetail = async () => {
      setLoading(true)
      setMessage('')

      try {
        const nextDetail = await loadAnnouncementById(selectedId)

        if (!active) {
          return
        }

        setDetail(nextDetail)

        if (nextDetail && !nextDetail.isRead) {
          await markAnnouncementRead(nextDetail.id)
          if (active) {
            setDetail({ ...nextDetail, isRead: true })
            setItems((current) =>
              current.map((item) =>
                item.id === nextDetail.id ? { ...item, isRead: true } : item,
              ),
            )
          }
        }
      } catch (error) {
        if (active) {
          setMessage(
            t('announcements.loadFailed', {
              detail:
                error instanceof Error
                  ? error.message
                  : t('announcements.unknownError'),
            }),
          )
        }
      } finally {
        if (active) {
          setLoading(false)
        }
      }
    }

    void loadDetail()

    return () => {
      active = false
    }
  }, [selectedId])

  return (
    <div className="app-shell">
      <AppHeader
        currentPage="announcements"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="announcements-main">
        {selectedId ? (
          <section className="announcements-detail">
            <button
              type="button"
              className="profile-back"
              onClick={onBackToList}
            >
              ← {t('announcements.back')}
            </button>

            {loading && !detail ? (
              <section className="app-loading-inline">
                <LoadingMark />
                <p>{t('announcements.loading')}</p>
              </section>
            ) : message ? (
              <p className="auth-message error">{message}</p>
            ) : !detail ? (
              <div className="empty-state">
                <h2>{t('announcements.notFoundTitle')}</h2>
                <p>{t('announcements.notFoundBody')}</p>
              </div>
            ) : (
              <article className="announcement-detail-card">
                <div className="announcement-detail-meta">
                  <CategoryMark category={detail.category} />
                  {detail.published_at ? (
                    <time dateTime={detail.published_at}>
                      {formatPublishedAt(detail.published_at)}
                    </time>
                  ) : null}
                </div>
                <h1>{detail.title}</h1>
                <p className="announcement-detail-body">{detail.body}</p>
              </article>
            )}
          </section>
        ) : (
          <>
            <section className="announcements-intro">
              <p className="dashboard-eyebrow">
                {formatGreekAllCaps(t('announcements.kicker'))}
              </p>
              <h1>{t('announcements.heading')}</h1>
              <p>{t('announcements.intro')}</p>
            </section>

            {message ? (
              <p className="auth-message error">{message}</p>
            ) : null}

            {loading ? (
              <section className="app-loading-inline">
                <LoadingMark />
                <p>{t('announcements.loading')}</p>
              </section>
            ) : items.length === 0 ? (
              <section className="empty-state">
                <h2>{t('announcements.emptyTitle')}</h2>
                <p>{t('announcements.emptyBody')}</p>
              </section>
            ) : (
              <section
                className="announcements-list"
                aria-label={t('announcements.heading')}
              >
                {items.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    className={`announcement-card${item.isRead ? '' : ' unread'}`}
                    onClick={() => onOpen(item.id)}
                  >
                    <span className="announcement-card-icon">
                      <CategoryMark category={item.category} />
                      {item.isRead ? null : (
                        <span
                          className="announcement-unread-dot"
                          aria-label={t('announcements.unread')}
                        />
                      )}
                    </span>
                    <span className="announcement-card-copy">
                      <strong>{item.title}</strong>
                      {item.published_at ? (
                        <time dateTime={item.published_at}>
                          {formatPublishedAt(item.published_at)}
                        </time>
                      ) : null}
                      <small>{previewAnnouncementBody(item.body)}</small>
                    </span>
                  </button>
                ))}
              </section>
            )}
          </>
        )}
      </main>
    </div>
  )
}
