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
import { usePlayerProfileNav } from '../lib/playerProfileNav'
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
  exact_scores: number
  correct_results: number
}

type ProfileHeader = {
  username: string
  rankPosition: number | null
  totalPoints: number | null
}

type ProfileStats = {
  totalPoints: number
  exactScores: number
  correctResults: number
}

type StatsState =
  | { status: 'loading' }
  | { status: 'unavailable' }
  | { status: 'ready'; stats: ProfileStats }

type PredictionsState =
  | { status: 'loading' }
  | { status: 'unavailable' }
  | { status: 'ready'; count: number }

export function PlayerProfilePage({
  profileUserId,
  currentPage,
  username,
  role,
  onNavigate,
  onLogout,
  onBack,
}: PlayerProfilePageProps) {
  const { viewerUserId } = usePlayerProfileNav()
  const [header, setHeader] = useState<ProfileHeader | null>(null)
  const [statsState, setStatsState] = useState<StatsState>({
    status: 'loading',
  })
  const [predictionsState, setPredictionsState] = useState<PredictionsState>({
    status: 'loading',
  })
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
      setStatsState({ status: 'loading' })
      setPredictionsState({ status: 'loading' })

      const { data: profileRow, error: profileLookupError } = await supabase
        .from('profiles')
        .select('username')
        .eq('id', profileUserId)
        .maybeSingle()

      if (cancelled) return

      if (profileLookupError) {
        setProfileError('Δεν φορτώθηκε το προφίλ.')
        setLoadingProfile(false)
        setStatsState({ status: 'unavailable' })
        setPredictionsState({ status: 'unavailable' })
        return
      }

      if (!profileRow) {
        setNotFound(true)
        setLoadingProfile(false)
        setStatsState({ status: 'unavailable' })
        setPredictionsState({ status: 'unavailable' })
        return
      }

      setHeader({
        username: profileRow.username as string,
        rankPosition: null,
        totalPoints: null,
      })
      setLoadingProfile(false)

      const canReadPredictions =
        profileUserId === viewerUserId || role === 'admin'

      const boardPromise = supabase.rpc('get_leaderboard')
      const predictionsPromise = canReadPredictions
        ? supabase
            .from('predictions')
            .select('id', { count: 'exact', head: true })
            .eq('user_id', profileUserId)
        : Promise.resolve(null)

      const [boardResult, predictionsResult] = await Promise.all([
        boardPromise,
        predictionsPromise,
      ])

      if (cancelled) return

      if (boardResult.error) {
        setStatsState({ status: 'unavailable' })
      } else {
        const row = ((boardResult.data ?? []) as LeaderboardRow[]).find(
          (entry) => entry.user_id === profileUserId,
        )

        if (row) {
          setHeader((current) =>
            current
              ? {
                  ...current,
                  rankPosition: row.rank_position,
                  totalPoints: row.total_points,
                }
              : current,
          )
          setStatsState({
            status: 'ready',
            stats: {
              totalPoints: row.total_points,
              exactScores: row.exact_scores,
              correctResults: row.correct_results,
            },
          })
        } else {
          setStatsState({ status: 'unavailable' })
        }
      }

      if (!predictionsResult) {
        setPredictionsState({ status: 'unavailable' })
      } else if (predictionsResult.error) {
        setPredictionsState({ status: 'unavailable' })
      } else {
        setPredictionsState({
          status: 'ready',
          count: predictionsResult.count ?? 0,
        })
      }
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
  }, [profileUserId, role, viewerUserId])

  const rankLine =
    header &&
    header.rankPosition !== null &&
    header.totalPoints !== null
      ? `#${header.rankPosition} · ${header.totalPoints} βαθμοί`
      : null

  const pointsValue =
    statsState.status === 'ready' ? statsState.stats.totalPoints : '—'
  const exactValue =
    statsState.status === 'ready' ? statsState.stats.exactScores : '—'
  const correctValue =
    statsState.status === 'ready' ? statsState.stats.correctResults : '—'
  const predictionsValue =
    predictionsState.status === 'ready' ? predictionsState.count : '—'

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

        {!notFound && !profileError && header ? (
          <section
            className="profile-stats"
            aria-label="Στατιστικά παίκτη"
            aria-busy={
              statsState.status === 'loading' ||
              predictionsState.status === 'loading'
            }
          >
            <article className="summary-card">
              <span>Συνολικοί βαθμοί</span>
              <strong>{pointsValue}</strong>
            </article>
            <article className="summary-card">
              <span>Ακριβή σκορ</span>
              <strong>{exactValue}</strong>
            </article>
            <article className="summary-card">
              <span>Σωστά αποτελέσματα</span>
              <strong>{correctValue}</strong>
            </article>
            <article className="summary-card">
              <span>Προβλέψεις</span>
              <strong>{predictionsValue}</strong>
              {predictionsState.status === 'ready' ? (
                <small>συνολικά</small>
              ) : null}
            </article>
          </section>
        ) : null}

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
