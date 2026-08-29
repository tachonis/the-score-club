import { useEffect, useState } from 'react'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { BadgeGrid } from '../components/BadgeGrid'
import { BadgeModal } from '../components/BadgeModal'
import { LoadingMark } from '../components/BrandAssets'
import {
  fetchEarnedBadges,
  type GroupedBadge,
} from '../lib/badges'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { supabase } from '../lib/supabase'

type PlayerProfilePageProps = {
  profileUserId: string
  currentPage: AppDestination
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
  onBack: () => void
}

type LeaderboardRow = {
  user_id: string
  rank_position: number
  total_points: number
}

type ProfileHeader = {
  username: string
  rankPosition: number | null
  totalPoints: number | null
}

export function PlayerProfilePage({
  profileUserId,
  currentPage,
  username,
  role,
  onNavigate,
  onLogout,
  onBack,
}: PlayerProfilePageProps) {
  const [header, setHeader] = useState<ProfileHeader | null>(null)
  const [badges, setBadges] = useState<GroupedBadge[]>([])
  const [selectedBadge, setSelectedBadge] = useState<GroupedBadge | null>(null)
  const [loadingProfile, setLoadingProfile] = useState(true)
  const [loadingBadges, setLoadingBadges] = useState(true)
  const [profileError, setProfileError] = useState('')
  const [badgesError, setBadgesError] = useState('')
  const [notFound, setNotFound] = useState(false)

  useEffect(() => {
    let cancelled = false

    const loadProfile = async () => {
      setLoadingProfile(true)
      setProfileError('')
      setNotFound(false)
      setHeader(null)

      const { data: profileRow, error: profileLookupError } = await supabase
        .from('profiles')
        .select('username')
        .eq('id', profileUserId)
        .maybeSingle()

      if (cancelled) return

      if (profileLookupError) {
        setProfileError('Δεν φορτώθηκε το προφίλ.')
        setLoadingProfile(false)
        return
      }

      if (!profileRow) {
        setNotFound(true)
        setLoadingProfile(false)
        return
      }

      const nextHeader: ProfileHeader = {
        username: profileRow.username as string,
        rankPosition: null,
        totalPoints: null,
      }

      const { data: board, error: boardError } = await supabase.rpc(
        'get_leaderboard',
      )

      if (!cancelled && !boardError) {
        const row = ((board ?? []) as LeaderboardRow[]).find(
          (entry) => entry.user_id === profileUserId,
        )

        if (row) {
          nextHeader.rankPosition = row.rank_position
          nextHeader.totalPoints = row.total_points
        }
      }

      if (cancelled) return

      setHeader(nextHeader)
      setLoadingProfile(false)
    }

    const loadBadges = async () => {
      setLoadingBadges(true)
      setBadgesError('')
      setBadges([])
      setSelectedBadge(null)

      try {
        const earned = await fetchEarnedBadges(profileUserId)

        if (cancelled) return

        setBadges(earned)
      } catch {
        if (cancelled) return

        setBadgesError('Δεν φορτώθηκαν τα badges.')
      } finally {
        if (!cancelled) {
          setLoadingBadges(false)
        }
      }
    }

    void loadProfile()
    void loadBadges()

    return () => {
      cancelled = true
    }
  }, [profileUserId])

  const rankLine =
    header &&
    header.rankPosition !== null &&
    header.totalPoints !== null
      ? `#${header.rankPosition} · ${header.totalPoints} βαθμοί`
      : null

  return (
    <div className="app-shell">
      <AppHeader
        currentPage={currentPage}
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="dashboard-main profile-main">
        <section className="profile-hero">
          <button type="button" className="profile-back" onClick={onBack}>
            ← Πίσω
          </button>

          {loadingProfile ? (
            <section className="app-loading-inline">
              <LoadingMark />
              <p>Φόρτωση προφίλ...</p>
            </section>
          ) : profileError ? (
            <p className="auth-message error">{profileError}</p>
          ) : notFound ? (
            <div className="empty-state">
              <h2>Προφίλ Παίκτη</h2>
              <p>Το προφίλ δεν βρέθηκε.</p>
            </div>
          ) : header ? (
            <>
              <p className="dashboard-eyebrow">
                {formatGreekAllCaps('Προφίλ Παίκτη')}
              </p>
              <h1>@{header.username}</h1>
              {rankLine ? <p className="profile-meta">{rankLine}</p> : null}
            </>
          ) : null}
        </section>

        {!notFound && !profileError ? (
          <section className="profile-badges" aria-labelledby="profile-badges-heading">
            <h2 id="profile-badges-heading">Badges</h2>

            {badgesError ? (
              <p className="auth-message error">{badgesError}</p>
            ) : loadingBadges ? (
              <section className="app-loading-inline">
                <LoadingMark />
                <p>Φόρτωση badges...</p>
              </section>
            ) : badges.length === 0 ? (
              <p className="profile-badges-empty">
                Δεν έχει ξεκλειδώσει ακόμη κάποιο badge.
              </p>
            ) : (
              <BadgeGrid badges={badges} onSelect={setSelectedBadge} />
            )}
          </section>
        ) : null}
      </main>

      {selectedBadge ? (
        <BadgeModal
          badge={selectedBadge}
          onClose={() => setSelectedBadge(null)}
        />
      ) : null}
    </div>
  )
}
