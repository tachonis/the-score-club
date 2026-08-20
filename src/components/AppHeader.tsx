import { useEffect, useState } from 'react'

export type AppDestination =
  | 'home'
  | 'predictions'
  | 'standings'
  | 'players-cup'
  | 'league-phase'
  | 'rules'
  | 'admin'

type AppHeaderProps = {
  currentPage: AppDestination
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

type NavigationItem = {
  destination: AppDestination
  desktopLabel: string
  mobileLabel: string
  icon: string
  adminOnly?: boolean
}

const navigationItems: NavigationItem[] = [
  {
    destination: 'home',
    desktopLabel: 'Αρχική',
    mobileLabel: 'Αρχική',
    icon: '⌂',
  },
  {
    destination: 'predictions',
    desktopLabel: 'Αγώνες & Προβλέψεις',
    mobileLabel: 'Αγώνες',
    icon: '⚽',
  },
  {
    destination: 'standings',
    desktopLabel: 'Βαθμολογία',
    mobileLabel: 'Βαθμοί',
    icon: '🏆',
  },
  {
    destination: 'players-cup',
    desktopLabel: 'Players Cup',
    mobileLabel: 'Κύπελλο',
    icon: '◈',
  },
  {
    destination: 'league-phase',
    desktopLabel: 'League Phase',
    mobileLabel: 'League Phase',
    icon: '▦',
  },
  {
    destination: 'rules',
    desktopLabel: 'Κανόνες',
    mobileLabel: 'Κανόνες',
    icon: '≡',
  },
  {
    destination: 'admin',
    desktopLabel: 'Διαχείριση',
    mobileLabel: 'Διαχείριση',
    icon: '⚙',
    adminOnly: true,
  },
]

const bottomDestinations: AppDestination[] = [
  'home',
  'predictions',
  'standings',
  'players-cup',
]

const overflowDestinations: AppDestination[] = [
  'league-phase',
  'rules',
  'admin',
]

export function AppHeader({
  currentPage,
  username,
  role,
  onNavigate,
  onLogout,
}: AppHeaderProps) {
  const [menuOpen, setMenuOpen] = useState(false)

  const availableItems = navigationItems.filter(
    (item) => !item.adminOnly || role === 'admin',
  )
  const bottomItems = availableItems.filter((item) =>
    bottomDestinations.includes(item.destination),
  )
  const overflowItems = availableItems.filter((item) =>
    overflowDestinations.includes(item.destination),
  )
  const overflowIsActive = overflowItems.some(
    (item) => item.destination === currentPage,
  )

  useEffect(() => {
    setMenuOpen(false)
  }, [currentPage])

  useEffect(() => {
    if (!menuOpen) return

    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setMenuOpen(false)
      }
    }

    document.addEventListener('keydown', closeOnEscape)
    return () => document.removeEventListener('keydown', closeOnEscape)
  }, [menuOpen])

  const navigate = (destination: AppDestination) => {
    setMenuOpen(false)
    onNavigate(destination)
  }

  return (
    <>
      <header className="app-header">
        <div className="app-header-inner">
          <button
            type="button"
            className="app-logo"
            onClick={() => navigate('home')}
            aria-label="Μετάβαση στην αρχική σελίδα"
          >
            <span className="app-logo-mark">TSC</span>
            <span className="app-logo-text">
              <strong>The Score Club</strong>
              <small>Football prediction game</small>
            </span>
          </button>

          <nav className="desktop-navigation" aria-label="Κύρια πλοήγηση">
            {availableItems.map((item) => {
              const isActive = item.destination === currentPage

              return (
                <button
                  key={item.destination}
                  type="button"
                  className={`nav-link ${
                    item.adminOnly ? 'admin-link' : ''
                  } ${isActive ? 'active' : ''}`}
                  onClick={() => navigate(item.destination)}
                  aria-current={isActive ? 'page' : undefined}
                >
                  {item.desktopLabel}
                </button>
              )
            })}
          </nav>

          <div className="user-menu">
            <div className="user-details">
              <strong>{username}</strong>
              <span>{role === 'admin' ? 'Administrator' : 'Player'}</span>
            </div>
            <button
              type="button"
              className="logout-button"
              onClick={() => void onLogout()}
            >
              Αποσύνδεση
            </button>
          </div>
        </div>
      </header>

      {menuOpen && (
        <>
          <button
            type="button"
            className="mobile-menu-backdrop"
            aria-label="Κλείσιμο μενού"
            onClick={() => setMenuOpen(false)}
          />
          <nav
            id="mobile-overflow-navigation"
            className="mobile-overflow-menu"
            aria-label="Περισσότερες σελίδες"
          >
            <div className="mobile-menu-heading">
              <span>Περισσότερα</span>
              <button
                type="button"
                onClick={() => setMenuOpen(false)}
                aria-label="Κλείσιμο μενού"
              >
                ×
              </button>
            </div>
            {overflowItems.map((item) => {
              const isActive = item.destination === currentPage

              return (
                <button
                  key={item.destination}
                  type="button"
                  className={`mobile-menu-item ${
                    item.adminOnly ? 'admin-item' : ''
                  } ${isActive ? 'active' : ''}`}
                  onClick={() => navigate(item.destination)}
                  aria-current={isActive ? 'page' : undefined}
                >
                  <span aria-hidden="true">{item.icon}</span>
                  <strong>{item.mobileLabel}</strong>
                  <small aria-hidden="true">›</small>
                </button>
              )
            })}
          </nav>
        </>
      )}

      <nav className="mobile-navigation" aria-label="Πλοήγηση κινητού">
        {bottomItems.map((item) => {
          const isActive = item.destination === currentPage

          return (
            <button
              key={item.destination}
              type="button"
              className={`mobile-nav-link ${isActive ? 'active' : ''}`}
              onClick={() => navigate(item.destination)}
              aria-current={isActive ? 'page' : undefined}
            >
              <span aria-hidden="true">{item.icon}</span>
              {item.mobileLabel}
            </button>
          )
        })}

        <button
          type="button"
          className={`mobile-nav-link ${
            overflowIsActive || menuOpen ? 'active' : ''
          }`}
          onClick={() => setMenuOpen((open) => !open)}
          aria-controls="mobile-overflow-navigation"
          aria-expanded={menuOpen}
        >
          <span aria-hidden="true">☰</span>
          Μενού
        </button>
      </nav>
    </>
  )
}
