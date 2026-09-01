import { t, type MessageKey } from '../i18n'

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

const KNOWN_RESULT_ERRORS: Record<string, MessageKey> = {
  'Active administrator privileges are required': 'admin.needAdmin',
  'Scores must be non-negative integers': 'admin.scoresMustBeInt',
  'Match not found': 'admin.matchNotFound',
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
      message: t('admin.bothScores'),
    }
  }

  if (/[.,]/.test(trimmed)) {
    return {
      ok: false,
      message: t('admin.integerScore'),
    }
  }

  if (/^-/.test(trimmed) || trimmed.includes('-')) {
    return {
      ok: false,
      message: t('admin.negativeScore'),
    }
  }

  if (!/^\d{1,2}$/.test(trimmed)) {
    return {
      ok: false,
      message: t('admin.invalidScore'),
    }
  }

  const parsed = Number.parseInt(trimmed, 10)

  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) {
    return {
      ok: false,
      message: t('admin.invalidScore'),
    }
  }

  if (parsed < 0) {
    return {
      ok: false,
      message: t('admin.negativeScore'),
    }
  }

  if (parsed > ADMIN_SCORE_MAX) {
    return {
      ok: false,
      message: t('admin.scoreTooHigh', { max: ADMIN_SCORE_MAX }),
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
      return t(known)
    }
  }

  return t('admin.saveFailed')
}
