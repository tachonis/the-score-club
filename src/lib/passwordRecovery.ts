import { supabase } from './supabase'
import { readDestinationFromHash } from './push'

const STORAGE_KEY = 'tsc-password-recovery'

const recoveryListeners = new Set<(active: boolean) => void>()

let recoveryActive = readStoredRecovery()

function readStoredRecovery() {
  try {
    return sessionStorage.getItem(STORAGE_KEY) === '1'
  } catch {
    return false
  }
}

function writeStoredRecovery(active: boolean) {
  try {
    if (active) {
      sessionStorage.setItem(STORAGE_KEY, '1')
    } else {
      sessionStorage.removeItem(STORAGE_KEY)
    }
  } catch {
    // Ignore private-mode / storage failures.
  }
}

function setRecoveryActive(active: boolean) {
  recoveryActive = active
  writeStoredRecovery(active)
  recoveryListeners.forEach((listener) => listener(active))
}

function clearNonPushHash() {
  const hash = window.location.hash

  if (!hash || hash === '#') return
  if (readDestinationFromHash(hash)) return

  window.history.replaceState(
    null,
    '',
    window.location.pathname + window.location.search,
  )
}

supabase.auth.onAuthStateChange((event) => {
  if (event === 'PASSWORD_RECOVERY') {
    setRecoveryActive(true)
    window.setTimeout(clearNonPushHash, 0)
    return
  }

  if (event === 'SIGNED_OUT') {
    setRecoveryActive(false)
  }
})

export const MIN_PASSWORD_LENGTH = 6

export const getPasswordRecoveryRedirectTo = () => window.location.origin

export const isPasswordRecoveryActive = () => recoveryActive

export const subscribePasswordRecovery = (
  listener: (active: boolean) => void,
) => {
  listener(recoveryActive)
  recoveryListeners.add(listener)

  return () => {
    recoveryListeners.delete(listener)
  }
}

export const clearPasswordRecovery = () => {
  setRecoveryActive(false)
  clearNonPushHash()
}

type AuthErrorLike = {
  message?: string
  code?: string
}

const includesAny = (value: string, fragments: string[]) =>
  fragments.some((fragment) => value.includes(fragment))

export const mapAuthError = (error: AuthErrorLike | null | undefined) => {
  if (!error) {
    return 'Παρουσιάστηκε πρόβλημα. Δοκίμασε ξανά.'
  }

  const code = (error.code ?? '').toLowerCase()
  const message = (error.message ?? '').toLowerCase()

  if (
    code === 'otp_expired' ||
    code === 'access_denied' ||
    includesAny(message, [
      'email link is invalid or has expired',
      'token has expired',
      'otp_expired',
      'auth session missing',
      'session missing',
    ]) ||
    (message.includes('expired') &&
      includesAny(message, ['link', 'token', 'otp', 'code'])) ||
    (message.includes('invalid') &&
      includesAny(message, ['link', 'token', 'otp']))
  ) {
    return 'Ο σύνδεσμος επαναφοράς έχει λήξει ή δεν είναι πλέον έγκυρος.'
  }

  if (
    code === 'weak_password' ||
    message.includes('password should be at least') ||
    message.includes('password is known to be weak') ||
    message.includes('weak password')
  ) {
    return 'Ο κωδικός πρέπει να έχει τουλάχιστον 6 χαρακτήρες.'
  }

  if (
    code === 'same_password' ||
    message.includes('different from the old password')
  ) {
    return 'Ο νέος κωδικός πρέπει να είναι διαφορετικός από τον τρέχοντα.'
  }

  if (
    includesAny(message, [
      'rate limit',
      'for security purposes',
      'over_request_rate',
    ])
  ) {
    return 'Έγιναν πολλά αιτήματα. Περίμενε λίγο και δοκίμασε ξανά.'
  }

  if (message.includes('invalid') && message.includes('email')) {
    return 'Το email δεν είναι έγκυρο.'
  }

  if (
    includesAny(message, ['failed to fetch', 'network', 'fetch failed'])
  ) {
    return 'Παρουσιάστηκε πρόβλημα. Δοκίμασε ξανά.'
  }

  return 'Παρουσιάστηκε πρόβλημα. Δοκίμασε ξανά.'
}

export const isRecoveryLinkError = (error: AuthErrorLike | null | undefined) =>
  mapAuthError(error) ===
  'Ο σύνδεσμος επαναφοράς έχει λήξει ή δεν είναι πλέον έγκυρος.'
