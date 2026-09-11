import {
  parsePushTarget,
  type PushTarget,
} from './pushDestination.ts'

export const PENDING_PUSH_STORAGE_KEY = 'tsc-pending-push-destination'

export type StorageLike = {
  getItem: (key: string) => string | null
  setItem: (key: string, value: string) => void
  removeItem: (key: string) => void
}

type PushNavigateMessage = {
  type?: string
  destination?: string
  announcement_id?: string
  url?: string
}

const listeners = new Set<() => void>()

let memoryPending: PushTarget | null = null
let captureInstalled = false

const notify = () => {
  listeners.forEach((listener) => listener())
}

const defaultStorage = (): StorageLike | null => {
  try {
    if (typeof sessionStorage === 'undefined') {
      return null
    }

    return sessionStorage
  } catch {
    return null
  }
}

const readStoredTarget = (storage: StorageLike | null): PushTarget | null => {
  if (!storage) {
    return null
  }

  try {
    const raw = storage.getItem(PENDING_PUSH_STORAGE_KEY)

    if (!raw) {
      return null
    }

    const parsed = JSON.parse(raw) as Partial<PushTarget>
    const destination =
      typeof parsed.destination === 'string' ? parsed.destination : ''
    const announcementId =
      typeof parsed.announcementId === 'string' ? parsed.announcementId : null
    const target = parsePushTarget(
      announcementId
        ? `${destination}/${announcementId}`
        : destination,
    )

    return target
  } catch {
    return null
  }
}

const writeStoredTarget = (
  storage: StorageLike | null,
  target: PushTarget | null,
) => {
  if (!storage) {
    return
  }

  try {
    if (!target) {
      storage.removeItem(PENDING_PUSH_STORAGE_KEY)
      return
    }

    storage.setItem(PENDING_PUSH_STORAGE_KEY, JSON.stringify(target))
  } catch {
    // Private mode / blocked storage must not break navigation.
  }
}

export const parsePushNavigateMessage = (
  data: unknown,
): PushTarget | null => {
  if (!data || typeof data !== 'object') {
    return null
  }

  const message = data as PushNavigateMessage

  if (message.type !== 'push-navigate') {
    return null
  }

  return (
    parsePushTarget(message.destination ?? '') ??
    parsePushTarget(message.url ?? '') ??
    (message.announcement_id
      ? parsePushTarget(`announcements/${message.announcement_id}`)
      : null)
  )
}

export const rememberPushTarget = (
  target: PushTarget,
  storage?: StorageLike,
) => {
  const store = storage ?? defaultStorage()

  if (!storage) {
    memoryPending = target
  }

  writeStoredTarget(store, target)
  notify()
}

export const peekPendingPushTarget = (
  storage?: StorageLike,
): PushTarget | null => {
  if (!storage && memoryPending) {
    return memoryPending
  }

  return readStoredTarget(storage ?? defaultStorage())
}

export const consumePendingPushTarget = (
  storage?: StorageLike,
): PushTarget | null => {
  const target = peekPendingPushTarget(storage)

  if (!target) {
    return null
  }

  if (!storage) {
    memoryPending = null
  }

  writeStoredTarget(storage ?? defaultStorage(), null)
  notify()
  return target
}

export const captureLocationPushTarget = (
  location: { hash: string; pathname: string },
  storage?: StorageLike,
): PushTarget | null => {
  const target =
    parsePushTarget(location.hash) ?? parsePushTarget(location.pathname)

  if (!target) {
    return peekPendingPushTarget(storage)
  }

  rememberPushTarget(target, storage)
  return target
}

export const canApplyPendingPushTarget = ({
  hasSession,
  hasProfile,
  passwordRecovery,
}: {
  hasSession: boolean
  hasProfile: boolean
  passwordRecovery: boolean
}) => hasSession && hasProfile && !passwordRecovery

export const resolveVisiblePushRoute = ({
  pending,
  appPage,
  announcementId,
}: {
  pending: PushTarget | null
  appPage: string
  announcementId: string | null
}) =>
  pending
    ? {
        destination: pending.destination,
        announcementId: pending.announcementId,
      }
    : {
        destination: appPage,
        announcementId,
      }

export const clearConsumedPushHash = (
  location: { hash: string; pathname: string; search: string },
  historyLike: { replaceState: (state: null, unused: string, url: string) => void },
) => {
  if (!location.hash) {
    return
  }

  historyLike.replaceState(null, '', location.pathname + location.search)
}

export const subscribePushNavigation = (listener: () => void) => {
  listener()
  listeners.add(listener)

  return () => {
    listeners.delete(listener)
  }
}

const onHashChange = () => {
  captureLocationPushTarget(window.location)
}

const onWorkerMessage = (event: MessageEvent) => {
  const target = parsePushNavigateMessage(event.data)

  if (target) {
    rememberPushTarget(target)
  }
}

export const installPushNavigationCapture = () => {
  if (captureInstalled || typeof window === 'undefined') {
    return
  }

  captureInstalled = true
  captureLocationPushTarget(window.location)
  window.addEventListener('hashchange', onHashChange)

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', onWorkerMessage)
  }
}

export const resetPushNavigationForTests = (storage?: StorageLike) => {
  memoryPending = null
  writeStoredTarget(storage ?? defaultStorage(), null)
}

installPushNavigationCapture()
