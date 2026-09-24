import {
  NEUTRAL_ACCENT,
  paletteForTeamName,
  type ShieldPalette,
} from '../lib/teamIdentity'

const SHIELD_PATH =
  'M8 3.5H56C58.2 3.5 60 5.4 60 8.2V30.5C60 46.2 46.8 60.4 32 72.5C17.2 60.4 4 46.2 4 30.5V8.2C4 5.4 5.8 3.5 8 3.5Z'

const CHIEF_PATH =
  'M8 3.5H56C58.2 3.5 60 5.4 60 8.2V22.5H4V8.2C4 5.4 5.8 3.5 8 3.5Z'

type PlayerShieldProps = {
  teamName?: string | null
  size?: number
  className?: string
  /** Set when the shield itself is the accessible name. Otherwise decorative. */
  label?: string
}

const strokeFor = (palette: ShieldPalette) =>
  palette.lightField
    ? { outer: '#F6F2E9', outerWidth: 3.4, inner: '#102C32', innerWidth: 2.5 }
    : { outer: '#F6F2E9', outerWidth: 2.6, inner: '#102C32', innerWidth: 1.15 }

export function PlayerShield({
  teamName = null,
  size = 32,
  className,
  label,
}: PlayerShieldProps) {
  const palette = paletteForTeamName(teamName)
  const stroke = strokeFor(palette)
  const decorative = !label

  return (
    <svg
      className={className ? `player-shield ${className}` : 'player-shield'}
      width={size}
      height={Math.round(size * (76 / 64))}
      viewBox="0 0 64 76"
      aria-hidden={decorative ? true : undefined}
      role={decorative ? undefined : 'img'}
      aria-label={decorative ? undefined : label}
      focusable="false"
    >
      <path
        d={SHIELD_PATH}
        fill="none"
        stroke={stroke.outer}
        strokeWidth={stroke.outerWidth}
        strokeLinejoin="round"
      />
      <path
        d={SHIELD_PATH}
        fill={palette.primary}
        stroke={stroke.inner}
        strokeWidth={stroke.innerWidth}
        strokeLinejoin="round"
      />
      <path d={CHIEF_PATH} fill={palette.secondary} />
      <path
        d="M8 22.5H56"
        fill="none"
        stroke={palette.lightField ? '#102C32' : NEUTRAL_ACCENT}
        strokeWidth="1.25"
        strokeLinecap="round"
      />
    </svg>
  )
}
