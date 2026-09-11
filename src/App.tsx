import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './lib/supabase'
import { PlayerProfileNavContext } from './lib/playerProfileNav'
import {
  clearPasswordRecovery,
  isPasswordRecoveryActive,
  isRecoveryLinkError,
  mapAuthError,
  subscribePasswordRecovery,
} from './lib/passwordRecovery'
import { syncPushSubscription } from './lib/push'
import {
  canApplyPendingPushTarget,
  clearConsumedPushHash,
  consumePendingPushTarget,
  peekPendingPushTarget,
  resolveVisiblePushRoute,
  subscribePushNavigation,
} from './lib/pushNavigation'
import type { AppDestination } from './components/AppHeader'
import { AdminPage } from './pages/AdminPage'
import { AnnouncementsPage } from './pages/AnnouncementsPage'
import { ContactPage } from './pages/ContactPage'
import { DashboardPage } from './pages/DashboardPage'
import { LoginPage } from './pages/LoginPage'
import { LeaguePhasePage } from './pages/LeaguePhasePage'
import { RegisterPage } from './pages/RegisterPage'
import { ResetPasswordPage } from './pages/ResetPasswordPage'
import { RulesModal } from './pages/RulesModal'
import { RulesPage } from './pages/RulesPage'
import { PredictionsPage } from './pages/PredictionsPage'
import { PlayerProfilePage } from './pages/PlayerProfilePage'
import { PlayersCupPage } from './pages/PlayersCupPage'
import { StandingsPage } from './pages/StandingsPage'
import { AuthLogo, LoadingSplashLogo } from './components/BrandAssets'
import { t } from './i18n'
import './auth.css'

type UserProfile = {
  username: string
  role: 'player' | 'admin'
  status: 'active' | 'disabled'
}

function App() {
  const [page, setPage] = useState<'login' | 'register'>('login')
  const [showRules, setShowRules] = useState(false)
  const [appPage, setAppPage] = useState<AppDestination>(
    () => peekPendingPushTarget()?.destination ?? 'home',
  )
  const [profileUserId, setProfileUserId] = useState<string | null>(null)
  const [announcementId, setAnnouncementId] = useState<string | null>(
    () => peekPendingPushTarget()?.announcementId ?? null,
  )
  const [navigationEpoch, setNavigationEpoch] = useState(0)
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [loadingSession, setLoadingSession] = useState(true)
  const [profileError, setProfileError] = useState('')
  const [passwordRecovery, setPasswordRecovery] = useState(
    isPasswordRecoveryActive,
  )

  useEffect(() => {
    const loadInitialSession = async () => {
      const { error: initError } = await supabase.auth.initialize()
      const { data, error } = await supabase.auth.getSession()

      if (initError && isRecoveryLinkError(initError)) {
        setProfileError(mapAuthError(initError))
      } else if (error) {
        setProfileError(t('auth.sessionCheckFailed'))
      }

      setSession(data.session)
      setLoadingSession(false)
    }

    void loadInitialSession()

    const unsubscribeRecovery = subscribePasswordRecovery(
      setPasswordRecovery,
    )

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)

      if (!nextSession) {
        setProfile(null)
        setProfileUserId(null)
      }
    })

    return () => {
      unsubscribeRecovery()
      subscription.unsubscribe()
    }
  }, [])

  useEffect(() => {
    if (!session?.user.id) {
      setProfile(null)
      return
    }

    const loadProfile = async () => {
      setProfileError('')

      const { data, error } = await supabase
        .from('profiles')
        .select('username, role, status')
        .eq('id', session.user.id)
        .single()

      if (error) {
        setProfileError(t('auth.profileLoadFailed'))
        return
      }

      const userProfile = data as UserProfile

      if (userProfile.status === 'disabled') {
        await supabase.auth.signOut()
        setProfileError(t('auth.accountDisabled'))
        return
      }

      setProfile(userProfile)
    }

    void loadProfile()
  }, [session])

  // Rebind this browser's existing push endpoint to the signed-in account.
  // Does not prompt for permission or create a new subscription. Logout does
  // not unsubscribe, so the same user can log back in still subscribed; a
  // different user on this device picks up the endpoint here, even if they
  // never open Home.
  const signedInUserId = session?.user.id ?? null
  const canSyncPush = Boolean(signedInUserId && profile && !passwordRecovery)

  useEffect(() => {
    if (!canSyncPush) {
      return
    }

    void syncPushSubscription().catch(() => {
      // A failed rebind must never block login or the rest of the app.
    })
  }, [canSyncPush, signedInUserId])

  useEffect(() => {
    return subscribePushNavigation(() => {
      setNavigationEpoch((value) => value + 1)
    })
  }, [])

  // Keep the tapped destination until session/profile are ready, including
  // messages that arrived before React mounted.
  useEffect(() => {
    if (
      !canApplyPendingPushTarget({
        hasSession: Boolean(session),
        hasProfile: Boolean(profile),
        passwordRecovery,
      })
    ) {
      return
    }

    const pending = peekPendingPushTarget()

    if (!pending) {
      return
    }

    consumePendingPushTarget()
    setAppPage(pending.destination)
    setAnnouncementId(pending.announcementId)
    setProfileUserId(null)
    clearConsumedPushHash(window.location, window.history)
  }, [navigationEpoch, session, profile, passwordRecovery])

  const handleLogout = async () => {
    const { error } = await supabase.auth.signOut()

    if (error) {
      setProfileError(t('auth.signOutFailed'))
      return
    }

    setProfileUserId(null)
    setAnnouncementId(null)
    setPage('login')
  }

  const handleNavigate = (destination: AppDestination) => {
    if (destination === 'admin' && profile?.role !== 'admin') {
      return
    }

    consumePendingPushTarget()
    setProfileUserId(null)
    setAnnouncementId(null)
    setAppPage(destination)
  }

  if (loadingSession) {
    return (
      <main className="app-loading">
        <LoadingSplashLogo />
        <p>{t('auth.loadingApp')}</p>
      </main>
    )
  }

  if (passwordRecovery) {
    return (
      <div className="auth-shell">
        <section className="auth-brand">
          <div className="brand-content">
            <AuthLogo />

            <div className="brand-rules">
              <p>{t('auth.rulesIntro')}</p>

              <button
                type="button"
                className="brand-rules-button"
                onClick={() => setShowRules(true)}
              >
                {t('auth.viewRules')}
              </button>
            </div>
          </div>
        </section>

        <section className="auth-content">
          <div className="auth-card">
            {profileError && (
              <p className="auth-message error">{profileError}</p>
            )}

            <ResetPasswordPage onCompleted={clearPasswordRecovery} />
          </div>
        </section>

        {showRules && (
          <RulesModal onClose={() => setShowRules(false)} />
        )}
      </div>
    )
  }

  if (session && !profile && !profileError) {
    return (
      <main className="app-loading">
        <LoadingSplashLogo />
        <p>{t('auth.loadingProfile')}</p>
      </main>
    )
  }

  if (session && profile) {
    const visibleRoute = resolveVisiblePushRoute({
      pending: peekPendingPushTarget(),
      appPage,
      announcementId,
    })
    const currentPage =
      visibleRoute.destination === 'admin' && profile.role !== 'admin'
        ? 'home'
        : (visibleRoute.destination as AppDestination)
    const selectedAnnouncementId = visibleRoute.announcementId

    let page = (
      <DashboardPage
        username={profile.username}
        role={profile.role}
        onNavigate={handleNavigate}
        onLogout={handleLogout}
      />
    )

    if (profileUserId) {
      page = (
        <PlayerProfilePage
          profileUserId={profileUserId}
          currentPage={currentPage}
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
          onBack={() => setProfileUserId(null)}
        />
      )
    } else if (currentPage === 'admin' && profile.role === 'admin') {
      page = (
        <AdminPage
          username={profile.username}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (currentPage === 'standings') {
      page = (
        <StandingsPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (currentPage === 'players-cup') {
      page = (
        <PlayersCupPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (currentPage === 'league-phase') {
      page = (
        <LeaguePhasePage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (currentPage === 'rules') {
      page = (
        <RulesPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (currentPage === 'contact') {
      page = (
        <ContactPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (currentPage === 'announcements') {
      page = (
        <AnnouncementsPage
          username={profile.username}
          role={profile.role}
          selectedId={selectedAnnouncementId}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
          onOpen={setAnnouncementId}
          onBackToList={() => setAnnouncementId(null)}
        />
      )
    } else if (currentPage === 'predictions') {
      page = (
        <PredictionsPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    }

    return (
      <PlayerProfileNavContext.Provider
        value={{
          viewerUserId: session.user.id,
          openProfile: setProfileUserId,
        }}
      >
        {page}
      </PlayerProfileNavContext.Provider>
    )
  }

  return (
    <div className="auth-shell">
      <section className="auth-brand">
        <div className="brand-content">
          <AuthLogo />

          <div className="brand-rules">
            <p>{t('auth.rulesIntro')}</p>

            <button
              type="button"
              className="brand-rules-button"
              onClick={() => setShowRules(true)}
            >
              {t('auth.viewRules')}
            </button>
          </div>
        </div>
      </section>

      <section className="auth-content">
        <div className="auth-card">
          <div className="auth-tabs">
            <button
              type="button"
              className={`auth-tab ${page === 'login' ? 'active' : ''}`}
              onClick={() => setPage('login')}
            >
              {t('auth.signIn')}
            </button>

            <button
              type="button"
              className={`auth-tab ${page === 'register' ? 'active' : ''}`}
              onClick={() => setPage('register')}
            >
              {t('auth.register')}
            </button>
          </div>

          {profileError && (
            <p className="auth-message error">{profileError}</p>
          )}

          {page === 'login' ? <LoginPage /> : <RegisterPage />}
        </div>
      </section>

      {showRules && (
        <RulesModal onClose={() => setShowRules(false)} />
      )}
    </div>
  )
}

export default App
