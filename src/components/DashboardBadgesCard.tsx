import { useEffect, useState } from 'react'
import { fetchUniqueEarnedBadgeCount } from '../lib/badges'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { usePlayerProfileNav } from '../lib/playerProfileNav'

const badgeCountCopy = (count: number) => {
  if (count === 0) {
    return 'Δεν έχεις ξεκλειδώσει ακόμη κάποιο badge'
  }

  if (count === 1) {
    return 'Έχεις ξεκλειδώσει 1 badge'
  }

  return `Έχεις ξεκλειδώσει ${count} badges`
}

export function DashboardBadgesCard() {
  const { viewerUserId, openProfile } = usePlayerProfileNav()
  const [count, setCount] = useState<number | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let cancelled = false

    const loadCount = async () => {
      try {
        const uniqueCount = await fetchUniqueEarnedBadgeCount(viewerUserId)

        if (!cancelled) {
          setCount(uniqueCount)
        }
      } catch {
        if (!cancelled) {
          setFailed(true)
        }
      }
    }

    void loadCount()

    return () => {
      cancelled = true
    }
  }, [viewerUserId])

  if (failed) {
    return null
  }

  if (count === null) {
    return (
      <div
        className="dashboard-badges-card dashboard-badges-card--loading"
        aria-busy="true"
        aria-live="polite"
      >
        <span className="dashboard-badges-icon" aria-hidden="true">
          <svg
            viewBox="0 0 24 24"
            width="18"
            height="18"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M12 3 19.2 6.1v5.4c0 4.5-3 8.4-7.2 9.5-4.2-1.1-7.2-5-7.2-9.5V6.1z" />
            <path d="M9.3 12.2 11.1 14l3.7-4.1" />
          </svg>
        </span>
        <div className="dashboard-badges-copy">
          <p className="dashboard-eyebrow">{formatGreekAllCaps('Badges')}</p>
          <p>Φόρτωση badges...</p>
        </div>
      </div>
    )
  }

  const copy = badgeCountCopy(count)

  return (
    <button
      type="button"
      className="dashboard-badges-card"
      onClick={() => openProfile(viewerUserId)}
      aria-label={`${copy}. Προβολή badges`}
    >
      <span className="dashboard-badges-icon" aria-hidden="true">
        <svg
          viewBox="0 0 24 24"
          width="18"
          height="18"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.75"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M12 3 19.2 6.1v5.4c0 4.5-3 8.4-7.2 9.5-4.2-1.1-7.2-5-7.2-9.5V6.1z" />
          <path d="M9.3 12.2 11.1 14l3.7-4.1" />
        </svg>
      </span>

      <div className="dashboard-badges-copy">
        <p className="dashboard-eyebrow">{formatGreekAllCaps('Badges')}</p>
        <p>{copy}</p>
      </div>

      <span className="dashboard-badges-action">Προβολή badges</span>
    </button>
  )
}
