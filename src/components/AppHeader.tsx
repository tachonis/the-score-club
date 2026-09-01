import { useEffect, useState } from 'react'
import { t } from '../i18n'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { usePlayerProfileNav } from '../lib/playerProfileNav'
import { HeaderLogo } from './BrandAssets'
import { NavIcon, type NavIconName } from './NavIcons'

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
  icon: NavIconName
  adminOnly?: boolean
}

const navigationItems: NavigationItem[] = [
  {
    destination: 'home',
    desktopLabel: t('nav.home'),
    mobileLabel: t('nav.home'),
    icon: 'home',
  },
  {
    destination: 'predictions',
    desktopLabel: t('nav.matches'),
    mobileLabel: t('nav.matchesShort'),
    icon: 'matches',
  },
  {
    destination: 'standings',
    desktopLabel: t('nav.standings'),
    mobileLabel: t('nav.standingsShort'),
    icon: 'standings',
  },
  {
    destination: 'players-cup',
    desktopLabel: t('nav.playersCup'),
    mobileLabel: t('nav.playersCupShort'),
    icon: 'cup',
  },
  {
    destination: 'league-phase',
    desktopLabel: t('nav.leaguePhase'),
    mobileLabel: t('nav.leaguePhase'),
    icon: 'league',
  },
  {
    destination: 'rules',
    desktopLabel: t('nav.rules'),
    mobileLabel: t('nav.rules'),
    icon: 'rules',
  },
  {
    destination: 'admin',
    desktopLabel: t('nav.admin'),
    mobileLabel: t('nav.admin'),
    icon: 'admin',
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
  const { viewerUserId, openProfile } = usePlayerProfileNav()

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
            aria-label={t('nav.goHome')}
          >
            <HeaderLogo />
          </button>

          <nav className="desktop-navigation" aria-label={t('nav.main')}>
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
              <button
                type="button"
                className="user-profile-button"
                onClick={() => openProfile(viewerUserId)}
                aria-label={t('nav.profileOf', { username })}
              >
                {username}
              </button>
              <span>{role === 'admin' ? t('common.admin') : t('common.player')}</span>
            </div>
            <button
              type="button"
              className="logout-button"
              onClick={() => void onLogout()}
            >
              {t('nav.signOut')}
            </button>
          </div>
        </div>
      </header>

      {menuOpen && (
        <>
          <button
            type="button"
            className="mobile-menu-backdrop"
            aria-label={t('nav.closeMenu')}
            onClick={() => setMenuOpen(false)}
          />
          <nav
            id="mobile-overflow-navigation"
            className="mobile-overflow-menu"
            aria-label={t('nav.morePages')}
          >
            <div className="mobile-menu-heading">
              <span>{formatGreekAllCaps(t('common.more'))}</span>
              <button
                type="button"
                onClick={() => setMenuOpen(false)}
                aria-label={t('nav.closeMenu')}
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
                  <NavIcon name={item.icon} />
                  <strong>{item.mobileLabel}</strong>
                  <small aria-hidden="true">›</small>
                </button>
              )
            })}
          </nav>
        </>
      )}

      <nav className="mobile-navigation" aria-label={t('nav.mobile')}>
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
              <NavIcon name={item.icon} />
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
          <NavIcon name="menu" />
          {t('common.menu')}
        </button>
      </nav>
    </>
  )
}
