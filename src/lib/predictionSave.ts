import { t } from '../i18n'

export type PredictionSaveErrorKind = 'locked' | 'generic'

export type LockedMatchLabel = {
  homeName: string
  awayName: string
}

export type PredictionSaveFeedback = {
  tone: 'success' | 'error'
  text: string
}

const UNREADABLE_TEXT = /^(?:\{\}|\[object object\]|null|undefined)$/i

const AUTH_OR_SESSION_SIGNALS = [
  'jwt',
  'not authenticated',
  'auth session missing',
  'session missing',
  'invalid api key',
  'pgrst301',
]

const LOCK_MESSAGE_SIGNALS = [
  'row-level security',
  'row level security',
  'rls policy',
  'violates row-level security policy',
]

const readString = (value: unknown) =>
  typeof value === 'string' ? value.trim() : ''

const collectedErrorBits = (error: unknown) => {
  const bits: string[] = []

  if (typeof error === 'string') {
    bits.push(error)
  } else if (error instanceof Error) {
    bits.push(error.message)
    bits.push(error.name)
  }

  if (error && typeof error === 'object') {
    const record = error as Record<string, unknown>

    for (const key of ['message', 'code', 'details', 'hint']) {
      const value = record[key]

      if (typeof value === 'string' && value.trim()) {
        bits.push(value)
      }
    }
  }

  return bits
    .map((bit) => bit.trim())
    .filter((bit) => bit && !UNREADABLE_TEXT.test(bit))
    .join(' ')
    .toLowerCase()
}

const readErrorCode = (error: unknown) => {
  if (!error || typeof error !== 'object') {
    return ''
  }

  return readString((error as Record<string, unknown>).code).toLowerCase()
}

export const classifyPredictionSaveError = (
  error: unknown,
): PredictionSaveErrorKind => {
  if (error == null) {
    return 'generic'
  }

  const haystack = collectedErrorBits(error)
  const code = readErrorCode(error)

  if (
    AUTH_OR_SESSION_SIGNALS.some((signal) => haystack.includes(signal)) ||
    code === 'pgrst301'
  ) {
    return 'generic'
  }

  if (LOCK_MESSAGE_SIGNALS.some((signal) => haystack.includes(signal))) {
    return 'locked'
  }

  if (
    haystack.includes('permission denied') &&
    (haystack.includes('predictions') || haystack.includes('policy'))
  ) {
    return 'locked'
  }

  return 'generic'
}

export const buildPredictionSaveFeedback = ({
  savedCount,
  lockedLabels,
  genericFailureCount,
}: {
  savedCount: number
  lockedLabels: LockedMatchLabel[]
  genericFailureCount: number
}): PredictionSaveFeedback => {
  const lockedCount = lockedLabels.length

  if (genericFailureCount > 0) {
    return {
      tone: 'error',
      text: t('predictions.saveSomeFailed'),
    }
  }

  if (savedCount > 0 && lockedCount === 0) {
    return {
      tone: 'success',
      text: t('predictions.savedCountOk', { count: savedCount }),
    }
  }

  if (savedCount === 0 && lockedCount > 0) {
    return {
      tone: 'error',
      text: t('predictions.allLockedNow'),
    }
  }

  if (savedCount > 0 && lockedCount === 1) {
    const match = lockedLabels[0]

    return {
      tone: 'error',
      text: t('predictions.oneJustLocked', {
        home: match.homeName,
        away: match.awayName,
      }),
    }
  }

  return {
    tone: 'error',
    text: t('predictions.manyJustLocked', { count: lockedCount }),
  }
}
