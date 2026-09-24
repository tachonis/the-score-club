import { useEffect, useState } from 'react'
import { t } from '../i18n'
import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { BadgeGrid } from '../components/BadgeGrid'
import { BadgeModal } from '../components/BadgeModal'
import { FavoriteTeamDialog } from '../components/FavoriteTeamDialog'
import { LoadingMark } from '../components/BrandAssets'
import { PlayerPredictionHistory } from '../components/PlayerPredictionHistory'
import { PlayerShield } from '../components/PlayerShield'
import {
  fetchEarnedBadges,
  type GroupedBadge,
} from '../lib/badges'
import {
  loadChampionsLeagueTeams,
  loadTeamById,
  teamsForPicker,
  type TeamChoice,
} from '../lib/favoriteTeam'
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
  favoriteTeamId: number | null
  favoriteTeamName: string | null
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
  const [currentTeams, setCurrentTeams] = useState<TeamChoice[]>([])
  const [editingFavorite, setEditingFavorite] = useState(false)
  const [savingFavorite, setSavingFavorite] = useState(false)
  const [favoriteMessage, setFavoriteMessage] = useState('')
  const [favoriteError, setFavoriteError] = useState('')

  useEffect(() => {
    let cancelled = false

    const loadProfile = async () => {
      setLoadingProfile(true)
      setProfileError('')
      setNotFound(false)
      setHeader(null)
      setEditingFavorite(false)
      setFavoriteMessage('')
      setFavoriteError('')
      setStatsState({ status: 'loading' })
      setPredictionsState({ status: 'loading' })

      const [profileResult, teams] = await Promise.all([
        supabase
          .from('profiles')
          .select('username, favorite_team_id')
          .eq('id', profileUserId)
          .maybeSingle(),
        loadChampionsLeagueTeams(),
      ])
      const profileRow = profileResult.data
      const profileLookupError = profileResult.error

      if (cancelled) return

      if (profileLookupError) {
        setProfileError(t('profile.loadFailed'))
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

      const favoriteTeamId =
        (profileRow.favorite_team_id as number | null) ?? null
      const listedTeam =
        teams.find((team) => team.id === favoriteTeamId) ?? null
      const savedTeam =
        favoriteTeamId !== null && !listedTeam
          ? await loadTeamById(favoriteTeamId)
          : listedTeam

      if (cancelled) return

      setCurrentTeams(teams)
      setHeader({
        username: profileRow.username as string,
        rankPosition: null,
        totalPoints: null,
        favoriteTeamId,
        favoriteTeamName: savedTeam?.name ?? null,
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

        setBadgesError(t('profile.loadBadgesFailed'))
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
      ? t('profile.rankLine', {
          rank: header.rankPosition,
          points: header.totalPoints,
        })
      : null

  const pointsValue =
    statsState.status === 'ready' ? statsState.stats.totalPoints : '—'
  const exactValue =
    statsState.status === 'ready' ? statsState.stats.exactScores : '—'
  const correctValue =
    statsState.status === 'ready' ? statsState.stats.correctResults : '—'
  const predictionsValue =
    predictionsState.status === 'ready' ? predictionsState.count : '—'
  const isOwnProfile = viewerUserId === profileUserId
  const pickerTeams = teamsForPicker(
    currentTeams,
    header?.favoriteTeamId && header.favoriteTeamName
      ? { id: header.favoriteTeamId, name: header.favoriteTeamName }
      : null,
  )

  const saveFavoriteTeam = async (favoriteTeamId: number | null) => {
    setSavingFavorite(true)
    setFavoriteError('')

    const { error } = await supabase
      .from('profiles')
      .update({ favorite_team_id: favoriteTeamId })
      .eq('id', profileUserId)

    if (error) {
      setFavoriteError(t('profile.favoriteTeamSaveFailed'))
      setSavingFavorite(false)
      return
    }

    const savedTeam =
      favoriteTeamId === null
        ? null
        : pickerTeams.find((team) => team.id === favoriteTeamId) ?? null

    setHeader((current) =>
      current
        ? {
            ...current,
            favoriteTeamId,
            favoriteTeamName: savedTeam?.name ?? null,
          }
        : current,
    )
    setFavoriteMessage(t('profile.favoriteTeamUpdated'))
    setSavingFavorite(false)
    setEditingFavorite(false)
  }

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
            ← {t('profile.back')}
          </button>

          {loadingProfile ? (
            <section className="app-loading-inline">
              <LoadingMark />
              <p>{t('auth.loadingProfile')}</p>
            </section>
          ) : profileError ? (
            <p className="auth-message error">{profileError}</p>
          ) : notFound ? (
            <div className="empty-state">
              <h2>{t('profile.title')}</h2>
              <p>{t('profile.notFound')}</p>
            </div>
          ) : header ? (
            <>
              <p className="dashboard-eyebrow">
                {formatGreekAllCaps(t('profile.title'))}
              </p>
              <div className="profile-identity">
                <PlayerShield
                  teamName={header.favoriteTeamName}
                  size={84}
                />
                <div className="profile-identity-copy">
                  <h1>@{header.username}</h1>
                  {header.favoriteTeamName ? (
                    <p className="profile-supports">
                      {t('profile.supports', { team: header.favoriteTeamName })}
                    </p>
                  ) : null}
                  {isOwnProfile ? (
                    <button
                      type="button"
                      className="profile-edit-button"
                      onClick={() => {
                        setFavoriteError('')
                        setFavoriteMessage('')
                        setEditingFavorite(true)
                      }}
                    >
                      {t('profile.editProfile')}
                    </button>
                  ) : null}
                </div>
              </div>
              {favoriteMessage ? (
                <p className="auth-message success">{favoriteMessage}</p>
              ) : null}
              {rankLine ? <p className="profile-meta">{rankLine}</p> : null}
            </>
          ) : null}
        </section>

        {!notFound && !profileError && header ? (
          <section
            className="profile-stats"
            aria-label={t('profile.statsAria')}
            aria-busy={
              statsState.status === 'loading' ||
              predictionsState.status === 'loading'
            }
          >
            <article className="summary-card">
              <span>{t('profile.totalPoints')}</span>
              <strong>{pointsValue}</strong>
            </article>
            <article className="summary-card">
              <span>{t('profile.exactScores')}</span>
              <strong>{exactValue}</strong>
            </article>
            <article className="summary-card">
              <span>{t('profile.correctResults')}</span>
              <strong>{correctValue}</strong>
            </article>
            <article className="summary-card">
              <span>{t('profile.predictions')}</span>
              <strong>{predictionsValue}</strong>
              {predictionsState.status === 'ready' ? (
                <small>{t('profile.predictionsTotal')}</small>
              ) : null}
            </article>
          </section>
        ) : null}

        {!notFound && !profileError ? (
          <section className="profile-badges" aria-labelledby="profile-badges-heading">
            <h2 id="profile-badges-heading">{t('badges.title')}</h2>

            {badgesError ? (
              <p className="auth-message error">{badgesError}</p>
            ) : loadingBadges ? (
              <section className="app-loading-inline">
                <LoadingMark />
                <p>{t('badges.loading')}</p>
              </section>
            ) : badges.length === 0 ? (
              <p className="profile-badges-empty">
                {t('profile.emptyBadges')}
              </p>
            ) : (
              <BadgeGrid badges={badges} onSelect={setSelectedBadge} />
            )}
          </section>
        ) : null}

        {!notFound && !profileError && header ? (
          <PlayerPredictionHistory
            key={profileUserId}
            profileUserId={profileUserId}
          />
        ) : null}
      </main>

      {selectedBadge ? (
        <BadgeModal
          badge={selectedBadge}
          onClose={() => setSelectedBadge(null)}
        />
      ) : null}

      {editingFavorite && header && isOwnProfile ? (
        <FavoriteTeamDialog
          teams={pickerTeams}
          favoriteTeamId={header.favoriteTeamId}
          saving={savingFavorite}
          errorMessage={favoriteError}
          onClose={() => {
            if (!savingFavorite) setEditingFavorite(false)
          }}
          onSave={(favoriteTeamId) => {
            void saveFavoriteTeam(favoriteTeamId)
          }}
        />
      ) : null}
    </div>
  )
}
