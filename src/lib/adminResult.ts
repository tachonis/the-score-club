export const ADMIN_SCORE_MAX = 20

export type PendingAdminResult = {
  matchId: number
  homeName: string
  awayName: string
  homeScore: number
  awayScore: number
  storedHomeScore: number | null
  storedAwayScore: number | null
  kind: 'entry' | 'correction'
}

type ParsedAdminScore =
  | { ok: true; value: number }
  | { ok: false; message: string }

const UNREADABLE_TEXT = /^(?:\{\}|\[object object\]|null|undefined)$/i

const KNOWN_RESULT_ERRORS: Record<string, string> = {
  'Active administrator privileges are required':
    'Η καταχώριση απαιτεί ενεργό λογαριασμό διαχειριστή.',
  'Scores must be non-negative integers':
    'Το σκορ πρέπει να είναι μη αρνητικός ακέραιος.',
  'Match not found': 'Ο αγώνας δεν βρέθηκε.',
}

const readString = (value: unknown) =>
  typeof value === 'string' ? value.trim() : ''

export const isAllowedAdminScoreDraft = (value: string) => {
  if (!/^\d{0,2}$/.test(value)) {
    return false
  }

  if (value === '') {
    return true
  }

  return Number(value) <= ADMIN_SCORE_MAX
}

export const parseAdminScore = (value: string): ParsedAdminScore => {
  const trimmed = value.trim()

  if (trimmed === '') {
    return {
      ok: false,
      message: 'Συμπλήρωσε και τα δύο πεδία σκορ 90 λεπτών.',
    }
  }

  if (/[.,]/.test(trimmed)) {
    return {
      ok: false,
      message: 'Το σκορ πρέπει να είναι ακέραιος αριθμός.',
    }
  }

  if (/^-/.test(trimmed) || trimmed.includes('-')) {
    return {
      ok: false,
      message: 'Το σκορ δεν μπορεί να είναι αρνητικό.',
    }
  }

  if (!/^\d{1,2}$/.test(trimmed)) {
    return {
      ok: false,
      message: 'Το σκορ δεν είναι έγκυρο.',
    }
  }

  const parsed = Number.parseInt(trimmed, 10)

  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
    return {
      ok: false,
      message: 'Το σκορ δεν είναι έγκυρο.',
    }
  }

  if (parsed < 0) {
    return {
      ok: false,
      message: 'Το σκορ δεν μπορεί να είναι αρνητικό.',
    }
  }

  if (parsed > ADMIN_SCORE_MAX) {
    return {
      ok: false,
      message: `Το σκορ δεν μπορεί να είναι πάνω από ${ADMIN_SCORE_MAX}.`,
    }
  }

  return { ok: true, value: parsed }
}

export const classifySetMatchResultError = (error: unknown) => {
  const bits: string[] = []

  if (typeof error === 'string') {
    bits.push(error)
  } else if (error instanceof Error) {
    bits.push(error.message)
  }

  if (error && typeof error === 'object') {
    const record = error as Record<string, unknown>
    const message = readString(record.message)

    if (message && !UNREADABLE_TEXT.test(message)) {
      bits.push(message)
    }
  }

  for (const bit of bits) {
    const known = KNOWN_RESULT_ERRORS[bit]

    if (known) {
      return known
    }
  }

  return 'Δεν αποθηκεύτηκε το αποτέλεσμα. Δοκίμασε ξανά.'
}
