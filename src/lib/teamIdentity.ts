/**
 * Curated shield colors for the current Champions League teams.
 *
 * Keyed by the canonical `teams.name` from the official 2026/27 seed.
 * Team ids are identity columns and are not stable across databases, so
 * names are the deterministic key. Colors are never stored in the database.
 */

export type ShieldPalette = {
  primary: string
  secondary: string
  /** White or near-white field. The shield draws a dark outer stroke. */
  lightField: boolean
}

export const NEUTRAL_SHIELD: ShieldPalette = {
  primary: '#183E45',
  secondary: '#D28B45',
  lightField: false,
}

export const NEUTRAL_ACCENT = '#F6F2E9'

const palette = (
  primary: string,
  secondary: string,
  lightField = false,
): ShieldPalette => ({ primary, secondary, lightField })

/** Canonical `teams.name` values. Do not key shorthand labels. */
export const TEAM_SHIELD_PALETTES: Record<string, ShieldPalette> = {
  'AEK Athens': palette('#F5C400', '#111111'),
  Arsenal: palette('#D71920', '#FFFFFF'),
  'Aston Villa': palette('#6A1538', '#95BFE5'),
  'Atlético Madrid': palette('#D71920', '#1C2C5B'),
  Barcelona: palette('#004D98', '#A50044'),
  'Bayern Munich': palette('#DC052D', '#FFFFFF'),
  'Bodø/Glimt': palette('#FFDD00', '#111111'),
  'Borussia Dortmund': palette('#FDE100', '#111111'),
  'Club Brugge': palette('#0057B8', '#111111'),
  'Como 1907': palette('#1E5AA8', '#FFFFFF'),
  Fenerbahçe: palette('#0B1F5B', '#FFD700'),
  Feyenoord: palette('#E30613', '#FFFFFF'),
  Galatasaray: palette('#A90432', '#FDB912'),
  'Inter Milan': palette('#0057B8', '#111111'),
  LASK: palette('#111111', '#FFFFFF'),
  'RB Leipzig': palette('#FFFFFF', '#D50032', true),
  Lens: palette('#E30613', '#FFD200'),
  Lille: palette('#D71920', '#1E2A44'),
  Liverpool: palette('#C8102E', '#FFFFFF'),
  'Manchester City': palette('#6CABDD', '#FFFFFF'),
  'Manchester United': palette('#DA291C', '#111111'),
  Napoli: palette('#12A0D7', '#FFFFFF'),
  'Paris Saint-Germain': palette('#004170', '#DA291C'),
  Porto: palette('#0057B8', '#FFFFFF'),
  'PSV Eindhoven': palette('#ED1B24', '#FFFFFF'),
  'Real Betis': palette('#00954C', '#FFFFFF'),
  'Real Madrid': palette('#FFFFFF', '#D4AF37', true),
  Roma: palette('#8E1F2D', '#F0BC42'),
  Sabah: palette('#111111', '#E94B8A'),
  'Shakhtar Donetsk': palette('#F36F21', '#111111'),
  'Slavia Prague': palette('#D71920', '#FFFFFF'),
  'Slovan Bratislava': palette('#6EC6E8', '#FFFFFF'),
  'Sporting CP': palette('#00843D', '#FFFFFF'),
  Stuttgart: palette('#FFFFFF', '#C80A32', true),
  Viking: palette('#102B4E', '#FFFFFF'),
  Villarreal: palette('#F7E017', '#0057B8'),
}

export const paletteForTeamName = (
  teamName: string | null | undefined,
): ShieldPalette => {
  if (!teamName) {
    return NEUTRAL_SHIELD
  }

  return TEAM_SHIELD_PALETTES[teamName] ?? NEUTRAL_SHIELD
}

export const isNeutralShield = (palette: ShieldPalette) =>
  palette.primary === NEUTRAL_SHIELD.primary &&
  palette.secondary === NEUTRAL_SHIELD.secondary &&
  palette.lightField === NEUTRAL_SHIELD.lightField
