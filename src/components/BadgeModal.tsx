import { useEffect } from 'react'
import { BadgeImage } from './BadgeGrid'
import {
  formatAwardContext,
  formatAwardDate,
  formatUnlockedCount,
  type GroupedBadge,
} from '../lib/badges'

type BadgeModalProps = {
  badge: GroupedBadge
  onClose: () => void
}

export function BadgeModal({ badge, onClose }: BadgeModalProps) {
  const { definition, count, awards } = badge
  const latest = awards[0]
  const latestContext = latest
    ? formatAwardContext(definition.code, latest.context)
    : null

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        onClose()
      }
    }

    document.addEventListener('keydown', handleKeyDown)
    document.body.classList.add('modal-open')

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.body.classList.remove('modal-open')
    }
  }, [onClose])

  return (
    <div
      className="rules-overlay"
      onClick={onClose}
      role="presentation"
    >
      <section
        className="badge-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="badge-modal-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="badge-modal-header">
          <p className="rules-eyebrow">Badge</p>
          <button
            type="button"
            className="rules-close"
            onClick={onClose}
            aria-label="Κλείσιμο badge"
          >
            ×
          </button>
        </header>

        <div className="badge-modal-body">
          <BadgeImage
            imagePath={definition.image_path}
            title={definition.title}
            className="badge-modal-image"
          />

          <h2 id="badge-modal-title">{definition.title}</h2>
          <p className="badge-modal-description">{definition.description}</p>

          {definition.repeatable ? (
            <div className="badge-modal-earned">
              <p className="badge-modal-unlock">
                {formatUnlockedCount(count)}
              </p>

              <ol className="badge-history">
                {awards.map((award) => {
                  const context = formatAwardContext(
                    definition.code,
                    award.context,
                  )
                  const date = formatAwardDate(award.earned_at)

                  return (
                    <li key={award.id}>
                      {award.matchday_label ? (
                        <strong>{award.matchday_label}</strong>
                      ) : null}
                      {date ? <span>{date}</span> : null}
                      {context ? <small>{context}</small> : null}
                    </li>
                  )
                })}
              </ol>
            </div>
          ) : (
            <div className="badge-modal-earned">
              <p className="badge-modal-unlock">Ξεκλειδώθηκε</p>
              {latest ? (
                <p className="badge-modal-date">
                  {formatAwardDate(latest.earned_at)}
                </p>
              ) : null}
              {latestContext ? (
                <p className="badge-modal-context">{latestContext}</p>
              ) : null}
            </div>
          )}
        </div>
      </section>
    </div>
  )
}
