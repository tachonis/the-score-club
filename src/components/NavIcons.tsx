type NavIconName =
  | 'home'
  | 'matches'
  | 'standings'
  | 'cup'
  | 'menu'
  | 'league'
  | 'rules'
  | 'admin'

const iconProps = {
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.75,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true as const,
  focusable: false as const,
}

export function NavIcon({ name }: { name: NavIconName }) {
  return (
    <svg className="nav-icon" width="22" height="22" {...iconProps}>
      {name === 'home' && (
        <path d="M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-5.2v-6.2H10.2V21H5a1 1 0 0 1-1-1z" />
      )}
      {name === 'matches' && (
        <>
          <circle cx="12" cy="12" r="8.25" />
          <path d="M12 3.75v16.5M3.75 12h16.5M6.2 6.2c2.2 1.7 4.7 2.5 5.8 2.5s3.6-.8 5.8-2.5M6.2 17.8c2.2-1.7 4.7-2.5 5.8-2.5s3.6.8 5.8 2.5" />
        </>
      )}
      {name === 'standings' && (
        <>
          <path d="M5 20V10" />
          <path d="M12 20V4" />
          <path d="M19 20v-7" />
        </>
      )}
      {name === 'cup' && (
        <>
          <path d="M8 4h8v3.2a4 4 0 0 1-8 0z" />
          <path d="M8 6.2H5.6A2.6 2.6 0 0 0 8 8.8" />
          <path d="M16 6.2h2.4A2.6 2.6 0 0 1 16 8.8" />
          <path d="M12 11.2V15" />
          <path d="M9 20h6" />
          <path d="M10.5 15h3L14 20h-4z" />
        </>
      )}
      {name === 'menu' && (
        <>
          <path d="M5 7h14" />
          <path d="M5 12h14" />
          <path d="M5 17h14" />
        </>
      )}
      {name === 'league' && (
        <>
          <rect x="4" y="4" width="7" height="7" rx="1" />
          <rect x="13" y="4" width="7" height="7" rx="1" />
          <rect x="4" y="13" width="7" height="7" rx="1" />
          <rect x="13" y="13" width="7" height="7" rx="1" />
        </>
      )}
      {name === 'rules' && (
        <>
          <path d="M7 4.5h10A1.5 1.5 0 0 1 18.5 6v14L12 17.2 5.5 20V6A1.5 1.5 0 0 1 7 4.5z" />
          <path d="M9 8.5h6" />
          <path d="M9 12h4" />
        </>
      )}
      {name === 'admin' && (
        <>
          <circle cx="12" cy="12" r="3.1" />
          <path d="M12 4.5v2.1M12 17.4v2.1M4.5 12h2.1M17.4 12h2.1M6.4 6.4l1.5 1.5M16.1 16.1l1.5 1.5M17.6 6.4l-1.5 1.5M7.9 16.1l-1.5 1.5" />
        </>
      )}
    </svg>
  )
}

export type { NavIconName }
