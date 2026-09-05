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
import { readDestinationFromHash, syncPushSubscription, type PushDestination } from './lib/push'
import type { AppDestination } from './components/AppHeader'
import { AdminPage } from './pages/AdminPage'
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
  const [appPage, setAppPage] = useState<AppDestination>('home')
  const [profileUserId, setProfileUserId] = useState<string | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [loadingSession, setLoadingSession] = useState(true)
  const [profileError, setProfileError] = useState('')
  const [passwordRecovery, setPasswordRecovery] = useState(
    isPasswordRecoveryActive,
  )
  const [pendingDestination, setPendingDestination] =
    useState<PushDestination | null>(() =>
      readDestinationFromHash(window.location.hash),
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

  // A tapped notification either opens /#<destination> or, when a window is
  // already open, arrives as a message from the push worker.
  useEffect(() => {
    const readHash = () => {
      const destination = readDestinationFromHash(window.location.hash)

      if (destination) {
        setPendingDestination(destination)
      }
    }

    const readWorkerMessage = (event: MessageEvent) => {
      const data = event.data as
        | { type?: string; destination?: string }
        | null

      if (data?.type !== 'push-navigate') return

      const destination = readDestinationFromHash(data.destination ?? '')

      if (destination) {
        setPendingDestination(destination)
      }
    }

    const worker =
      'serviceWorker' in navigator ? navigator.serviceWorker : null

    window.addEventListener('hashchange', readHash)
    worker?.addEventListener('message', readWorkerMessage)

    return () => {
      window.removeEventListener('hashchange', readHash)
      worker?.removeEventListener('message', readWorkerMessage)
    }
  }, [])

  // The requested page is kept until the session and profile are ready, so a
  // notification tap survives the login screen.
  useEffect(() => {
    if (
      !pendingDestination ||
      !session ||
      !profile ||
      passwordRecovery
    ) {
      return
    }

    setAppPage(pendingDestination)
    setPendingDestination(null)

    if (window.location.hash) {
      window.history.replaceState(
        null,
        '',
        window.location.pathname + window.location.search,
      )
    }
  }, [pendingDestination, session, profile, passwordRecovery])

  const handleLogout = async () => {
    const { error } = await supabase.auth.signOut()

    if (error) {
      setProfileError(t('auth.signOutFailed'))
      return
    }

    setProfileUserId(null)
    setPage('login')
  }

  const handleNavigate = (destination: AppDestination) => {
    if (destination === 'admin' && profile?.role !== 'admin') {
      return
    }

    setProfileUserId(null)
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
    const currentPage =
      appPage === 'admin' && profile.role !== 'admin' ? 'home' : appPage

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
    } else if (appPage === 'admin' && profile.role === 'admin') {
      page = (
        <AdminPage
          username={profile.username}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (appPage === 'standings') {
      page = (
        <StandingsPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (appPage === 'players-cup') {
      page = (
        <PlayersCupPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (appPage === 'league-phase') {
      page = (
        <LeaguePhasePage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (appPage === 'rules') {
      page = (
        <RulesPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (appPage === 'contact') {
      page = (
        <ContactPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    } else if (appPage === 'predictions') {
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
