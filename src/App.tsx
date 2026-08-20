import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './lib/supabase'
import { readDestinationFromHash, type PushDestination } from './lib/push'
import type { AppDestination } from './components/AppHeader'
import { AdminPage } from './pages/AdminPage'
import { DashboardPage } from './pages/DashboardPage'
import { LoginPage } from './pages/LoginPage'
import { LeaguePhasePage } from './pages/LeaguePhasePage'
import { RegisterPage } from './pages/RegisterPage'
import { RulesModal } from './pages/RulesModal'
import { RulesPage } from './pages/RulesPage'
import { PredictionsPage } from './pages/PredictionsPage'
import { PlayersCupPage } from './pages/PlayersCupPage'
import { StandingsPage } from './pages/StandingsPage'
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
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [loadingSession, setLoadingSession] = useState(true)
  const [profileError, setProfileError] = useState('')
  const [pendingDestination, setPendingDestination] =
    useState<PushDestination | null>(() =>
      readDestinationFromHash(window.location.hash),
    )

  useEffect(() => {
    const loadInitialSession = async () => {
      const { data, error } = await supabase.auth.getSession()

      if (error) {
        setProfileError('Δεν ήταν δυνατός ο έλεγχος της σύνδεσης.')
      }

      setSession(data.session)
      setLoadingSession(false)
    }

    void loadInitialSession()

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)

      if (!nextSession) {
        setProfile(null)
      }
    })

    return () => {
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
        setProfileError(
          'Ο λογαριασμός συνδέθηκε, αλλά δεν φορτώθηκε το προφίλ.',
        )
        return
      }

      const userProfile = data as UserProfile

      if (userProfile.status === 'disabled') {
        await supabase.auth.signOut()
        setProfileError('Ο λογαριασμός σου είναι απενεργοποιημένος.')
        return
      }

      setProfile(userProfile)
    }

    void loadProfile()
  }, [session])

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
    if (!pendingDestination || !session || !profile) return

    setAppPage(pendingDestination)
    setPendingDestination(null)

    if (window.location.hash) {
      window.history.replaceState(
        null,
        '',
        window.location.pathname + window.location.search,
      )
    }
  }, [pendingDestination, session, profile])

  const handleLogout = async () => {
    const { error } = await supabase.auth.signOut()

    if (error) {
      setProfileError('Δεν ολοκληρώθηκε η αποσύνδεση.')
      return
    }

    setPage('login')
  }

  const handleNavigate = (destination: AppDestination) => {
    if (destination === 'admin' && profile?.role !== 'admin') {
      return
    }

    setAppPage(destination)
  }

  if (loadingSession) {
    return (
      <main className="app-loading">
        <div className="loading-mark">TSC</div>
        <p>Φόρτωση The Score Club...</p>
      </main>
    )
  }

  if (session && !profile && !profileError) {
    return (
      <main className="app-loading">
        <div className="loading-mark">TSC</div>
        <p>Φόρτωση προφίλ...</p>
      </main>
    )
  }

  if (session && profile) {
    if (appPage === 'admin' && profile.role === 'admin') {
      return (
        <AdminPage
          username={profile.username}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    }

    if (appPage === 'standings') {
      return (
        <StandingsPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    }

    if (appPage === 'players-cup') {
      return (
        <PlayersCupPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    }

    if (appPage === 'league-phase') {
      return (
        <LeaguePhasePage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    }

    if (appPage === 'rules') {
      return (
        <RulesPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    }

    if (appPage === 'predictions') {
      return (
        <PredictionsPage
          username={profile.username}
          role={profile.role}
          onNavigate={handleNavigate}
          onLogout={handleLogout}
        />
      )
    }

    return (
      <DashboardPage
        username={profile.username}
        role={profile.role}
        onNavigate={handleNavigate}
        onLogout={handleLogout}
      />
    )
  }

  return (
    <div className="auth-shell">
      <section className="auth-brand">
        <div className="brand-content">
          <div className="brand-badge" aria-hidden="true">
            <span>
              TSC
              <br />
              2:1
            </span>
          </div>

          <h1 className="brand-title">
            <span>THE SCORE</span>
            <span>CLUB</span>
          </h1>

          <p className="brand-subtitle">Football prediction game</p>

          <div className="brand-rules">
            <p>
              Διάβασε πώς παίζεται το The Score Club και δες τους
              επίσημους κανόνες πριν ξεκινήσεις.
            </p>

            <button
              type="button"
              className="brand-rules-button"
              onClick={() => setShowRules(true)}
            >
              Προβολή κανόνων
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
              Σύνδεση
            </button>

            <button
              type="button"
              className={`auth-tab ${page === 'register' ? 'active' : ''}`}
              onClick={() => setPage('register')}
            >
              Εγγραφή
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
