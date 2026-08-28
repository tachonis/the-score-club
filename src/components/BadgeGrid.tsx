import { useEffect, useState } from 'react'
import {
  optimizedBadgeImagePath,
  type GroupedBadge,
} from '../lib/badges'

type BadgeImageProps = {
  imagePath: string
  title: string
  className?: string
}

export function BadgeImage({ imagePath, title, className }: BadgeImageProps) {
  const [useFallback, setUseFallback] = useState(false)

  useEffect(() => {
    setUseFallback(false)
  }, [imagePath])

  return (
    <img
      src={useFallback ? imagePath : optimizedBadgeImagePath(imagePath)}
      alt={title}
      className={className}
      onError={() => {
        if (!useFallback) setUseFallback(true)
      }}
    />
  )
}

type BadgeGridProps = {
  badges: GroupedBadge[]
  onSelect: (badge: GroupedBadge) => void
}

export function BadgeGrid({ badges, onSelect }: BadgeGridProps) {
  return (
    <div className="badge-grid">
      {badges.map((badge) => (
        <button
          key={badge.code}
          type="button"
          className="badge-tile"
          onClick={() => onSelect(badge)}
          aria-label={
            badge.count > 1
              ? `${badge.definition.title}, ${badge.count} φορές`
              : badge.definition.title
          }
        >
          {badge.count > 1 ? (
            <span className="badge-repeat-chip" aria-hidden="true">
              ×{badge.count}
            </span>
          ) : null}

          <BadgeImage
            imagePath={badge.definition.image_path}
            title={badge.definition.title}
            className="badge-tile-image"
          />

          <span className="badge-tile-title">{badge.definition.title}</span>
        </button>
      ))}
    </div>
  )
}
