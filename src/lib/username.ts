export const MIN_USERNAME_LENGTH = 3
export const MAX_USERNAME_LENGTH = 30

// Keep in sync with profiles_username_format_check in
// supabase/migrations/20260829160000_profiles_username_format.sql
// Latin A–Z, modern Greek letters including monotonic accents, digits, _ - .
export const USERNAME_PATTERN = /^[A-Za-z0-9_.ΆΈ-ΊΌΎ-ώ-]+$/

export const USERNAME_INVALID_MESSAGE =
  'Το username μπορεί να περιέχει μόνο γράμματα, αριθμούς, τελεία, παύλα και κάτω παύλα.'

export const USERNAME_TOO_SHORT_MESSAGE =
  'Το username πρέπει να έχει τουλάχιστον 3 χαρακτήρες.'

export const USERNAME_TOO_LONG_MESSAGE =
  'Το username μπορεί να έχει έως 30 χαρακτήρες.'

export const USERNAME_CONSTRAINT_MESSAGE =
  'Το username δεν είναι έγκυρο. Χρησιμοποίησε 3–30 χαρακτήρες χωρίς κενά.'

export const REGISTER_GENERIC_MESSAGE =
  'Δεν ολοκληρώθηκε η εγγραφή. Δοκίμασε ξανά.'

const UNREADABLE_TEXT = /^(?:\{\}|\[object object\]|null|undefined)$/i

export const validateUsername = (value: string) => {
  const username = value.trim()

  if (username.length < MIN_USERNAME_LENGTH) {
    return USERNAME_TOO_SHORT_MESSAGE
  }

  if (username.length > MAX_USERNAME_LENGTH) {
    return USERNAME_TOO_LONG_MESSAGE
  }

  if (!USERNAME_PATTERN.test(username)) {
    return USERNAME_INVALID_MESSAGE
  }

  return null
}

const isUsableErrorText = (value: string) => {
  const text = value.trim()

  if (!text) return false
  if (UNREADABLE_TEXT.test(text)) return false
  if (text.startsWith('{') || text.startsWith('[')) return false

  return true
}

const readStringField = (value: unknown) =>
  typeof value === 'string' && isUsableErrorText(value) ? value.trim() : null

export const readErrorText = (error: unknown) => {
  if (error == null) return null

  if (typeof error === 'string') {
    return readStringField(error)
  }

  if (error instanceof Error) {
    return readStringField(error.message)
  }

  if (typeof error === 'object') {
    const record = error as Record<string, unknown>

    for (const key of ['message', 'error_description', 'error', 'msg']) {
      const text = readStringField(record[key])

      if (text) return text
    }
  }

  return null
}

const collectedErrorBits = (error: unknown) => {
  const bits: string[] = []

  if (typeof error === 'string') {
    bits.push(error)
  } else if (error instanceof Error) {
    bits.push(error.message)
    bits.push(error.name)
  } else if (error && typeof error === 'object') {
    const record = error as Record<string, unknown>

    for (const key of ['message', 'code', 'error_description', 'error', 'msg']) {
      const value = record[key]

      if (typeof value === 'string') {
        bits.push(value)
      }
    }
  }

  return bits.join(' ').toLowerCase()
}

export const mapUsernameConstraintError = (error: unknown) => {
  const haystack = collectedErrorBits(error)

  if (
    haystack.includes('23514') ||
    haystack.includes('profiles_username_format') ||
    (haystack.includes('check constraint') && haystack.includes('username'))
  ) {
    return USERNAME_CONSTRAINT_MESSAGE
  }

  return null
}

const isInternalAuthText = (text: string) => {
  const value = text.toLowerCase()

  return (
    value.includes('database error saving new user') ||
    value.includes('profiles_username_format') ||
    value.includes('check constraint') ||
    value.includes('postgres') ||
    value.includes('violates') ||
    value.includes('pgrst')
  )
}

export const mapRegisterError = (error: unknown) => {
  const constraintMessage = mapUsernameConstraintError(error)

  if (constraintMessage) {
    return constraintMessage
  }

  const text = readErrorText(error)

  if (text && !isInternalAuthText(text)) {
    return `Δεν ολοκληρώθηκε η εγγραφή: ${text}`
  }

  return REGISTER_GENERIC_MESSAGE
}
