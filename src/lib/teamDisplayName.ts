/**
 * Compact display names for mobile team labels on prediction cards.
 *
 * Keyed on the exact `name` value stored in the `teams` table.
 * If a team is not in this map the fallback logic below is used instead.
 *
 * Target: one line at 0.82rem on a ~140px column (390px card, 3-col grid,
 * ~12px side padding each side of the column). Roughly ≤14–15 characters.
 */
const COMPACT_NAMES: Record<string, string> = {
  // ── Group A / standard English spellings ──────────────────────────────
  'Real Madrid':                  'Real Madrid',
  'Manchester City':              'Man City',
  'Manchester United':            'Man United',
  'Arsenal':                      'Arsenal',
  'Liverpool':                    'Liverpool',
  'Chelsea':                      'Chelsea',
  'Tottenham Hotspur':            'Tottenham',
  'Aston Villa':                  'Aston Villa',

  // ── German ────────────────────────────────────────────────────────────
  'Bayern Munich':                'Bayern',
  'FC Bayern München':            'Bayern',
  'Bayern München':               'Bayern',
  'Borussia Dortmund':            'Dortmund',
  'Bayer Leverkusen':             'Leverkusen',
  'RB Leipzig':                   'RB Leipzig',
  'VfB Stuttgart':                'Stuttgart',
  'Eintracht Frankfurt':          'Frankfurt',
  'Borussia Mönchengladbach':     'M\'gladbach',
  'Sturm Graz':                   'Sturm Graz',

  // ── Spanish ───────────────────────────────────────────────────────────
  'FC Barcelona':                 'Barcelona',
  'Barcelona':                    'Barcelona',
  'Atlético de Madrid':           'Atlético',
  'Atletico de Madrid':           'Atlético',
  'Atlético Madrid':              'Atlético',
  'Atletico Madrid':              'Atlético',
  'Sevilla':                      'Sevilla',
  'Sevilla FC':                   'Sevilla',
  'Real Sociedad':                'R. Sociedad',
  'Girona':                       'Girona',
  'Real Betis':                   'R. Betis',

  // ── Italian ───────────────────────────────────────────────────────────
  'Inter Milan':                  'Inter',
  'FC Internazionale':            'Inter',
  'Internazionale':               'Inter',
  'Inter':                        'Inter',
  'AC Milan':                     'AC Milan',
  'Milan':                        'AC Milan',
  'Juventus':                     'Juventus',
  'Napoli':                       'Napoli',
  'AS Roma':                      'Roma',
  'Roma':                         'Roma',
  'Atalanta':                     'Atalanta',
  'Bologna':                      'Bologna',
  'Fiorentina':                   'Fiorentina',

  // ── French ────────────────────────────────────────────────────────────
  'Paris Saint-Germain':          'PSG',
  'PSG':                          'PSG',
  'Monaco':                       'Monaco',
  'AS Monaco':                    'Monaco',
  'Lille':                        'Lille',
  'Stade Brestois 29':            'Brest',
  'Brest':                        'Brest',

  // ── Portuguese ────────────────────────────────────────────────────────
  'Benfica':                      'Benfica',
  'SL Benfica':                   'Benfica',
  'Porto':                        'Porto',
  'FC Porto':                     'Porto',
  'Sporting CP':                  'Sporting CP',
  'Sporting Clube de Portugal':   'Sporting CP',

  // ── Dutch ─────────────────────────────────────────────────────────────
  'PSV Eindhoven':                'PSV',
  'PSV':                          'PSV',
  'Feyenoord':                    'Feyenoord',
  'AFC Ajax':                     'Ajax',
  'Ajax':                         'Ajax',

  // ── Belgian ───────────────────────────────────────────────────────────
  'Club Brugge':                  'Club Brugge',
  'Club Brugge KV':               'Club Brugge',

  // ── Scottish ──────────────────────────────────────────────────────────
  'Celtic':                       'Celtic',
  'Rangers':                      'Rangers',

  // ── Austrian ──────────────────────────────────────────────────────────
  'Red Bull Salzburg':            'Salzburg',
  'RB Salzburg':                  'Salzburg',

  // ── Norwegian ─────────────────────────────────────────────────────────
  'Bodø/Glimt':                   'Bodø/Glimt',
  'FK Bodø/Glimt':                'Bodø/Glimt',

  // ── Ukrainian / Eastern European ─────────────────────────────────────
  'Shakhtar Donetsk':             'Shakhtar',
  'Dinamo Zagreb':                'Din. Zagreb',
  'Dinamo Kyiv':                  'Din. Kyiv',
  'GNK Dinamo':                   'Din. Zagreb',
  'Slavia Prague':                'Slavia',
  'SK Slavia Praha':              'Slavia',
  'Sparta Prague':                'Sparta',
  'AC Sparta Praha':              'Sparta',

  // ── Other ─────────────────────────────────────────────────────────────
  'Young Boys':                   'Young Boys',
  'BSC Young Boys':               'Young Boys',
  'Crvena zvezda':                'Red Star',
  'Red Star Belgrade':            'Red Star',
  'Galatasaray':                  'Galatasaray',
  'Fenerbahçe':                   'Fenerbahçe',
  'Besiktas':                     'Beşiktaş',
  'Beşiktaş':                     'Beşiktaş',
}

/**
 * Derives a compact mobile label from a full team name when the team is
 * not in COMPACT_NAMES. Strips generic prefixes (FC, AC, AS, SK, GNK, etc.)
 * and returns at most the first two meaningful words, capped at 15 chars.
 */
function deriveCompact(fullName: string): string {
  const prefixes = /^(FC|AC|AS|SS|SK|GNK|RB|VfB|VfL|SL|BSC|BK|IF|IFK|HNK|NK|FK|SC|RC|CF|CD|UD|SD|RCD|CA|CE)\s+/i
  const stripped = fullName.replace(prefixes, '').trim()

  // Take first two words
  const words = stripped.split(/\s+/)
  const twoWords = words.slice(0, 2).join(' ')

  return twoWords.length <= 15 ? twoWords : words[0]
}

/**
 * Returns the compact display name for a team, for use in mobile card labels.
 * Uses the explicit map first, then derives from the full name.
 */
export function getCompactTeamName(
  fullName: string,
  shortName: string | null,
): string {
  // Explicit map takes priority
  if (COMPACT_NAMES[fullName]) {
    return COMPACT_NAMES[fullName]
  }

  // If short_name is set and looks like a real word (not 2–3 all-caps letters), use it
  if (
    shortName &&
    shortName.length > 3 &&
    !/^[A-Z]{2,4}$/.test(shortName)
  ) {
    return shortName
  }

  // Derive from full name
  return deriveCompact(fullName)
}
