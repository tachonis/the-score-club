import { supabase } from './supabase'

export const pushDestinations = [
  'home',
  'predictions',
  'standings',
  'league-phase',
  'rules',
] as const

export type PushDestination = (typeof pushDestinations)[number]

export type PushAvailability = 'ready' | 'ios-needs-install' | 'unsupported'

export type PushPermission = 'default' | 'granted' | 'denied'

export type PushStatus = {
  availability: PushAvailability
  permission: PushPermission
  subscribed: boolean
}

const vapidPublicKey: string = import.meta.env.VITE_VAPID_PUBLIC_KEY ?? ''

const serviceWorkerUrl = '/sw.js'

const isPushDestination = (value: string): value is PushDestination =>
  (pushDestinations as readonly string[]).includes(value)

export const readDestinationFromHash = (
  hash: string,
): PushDestination | null => {
  const value = hash.replace(/^#/, '').trim()

  return isPushDestination(value) ? value : null
}

const hasPushApis = () =>
  typeof window !== 'undefined' &&
  'serviceWorker' in navigator &&
  'PushManager' in window &&
  'Notification' in window

const isIosDevice = () =>
  /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)

const isInstalledApp = () =>
  window.matchMedia('(display-mode: standalone)').matches ||
  (navigator as Navigator & { standalone?: boolean }).standalone === true

export const readPushAvailability = (): PushAvailability => {
  if (typeof window === 'undefined' || vapidPublicKey === '') {
    return 'unsupported'
  }

  // On iPhone and iPad the push APIs only exist inside the Home Screen app,
  // so a plain Safari tab needs installation instructions instead of a button.
  if (isIosDevice() && !isInstalledApp()) {
    return 'ios-needs-install'
  }

  return hasPushApis() ? 'ready' : 'unsupported'
}

const readPermission = (): PushPermission => {
  if (typeof window === 'undefined' || !('Notification' in window)) {
    return 'default'
  }

  const permission = Notification.permission

  return permission === 'granted' || permission === 'denied'
    ? permission
    : 'default'
}

const toApplicationServerKey = (base64Url: string) => {
  const padding = '='.repeat((4 - (base64Url.length % 4)) % 4)
  const base64 = (base64Url + padding).replace(/-/g, '+').replace(/_/g, '/')
  const binary = window.atob(base64)
  const key = new Uint8Array(binary.length)

  for (let index = 0; index < binary.length; index += 1) {
    key[index] = binary.charCodeAt(index)
  }

  return key
}

const matchesCurrentKey = (subscription: PushSubscription) => {
  const subscribedKey = subscription.options.applicationServerKey

  if (!subscribedKey) return false

  const current = toApplicationServerKey(vapidPublicKey)
  const stored = new Uint8Array(subscribedKey)

  return (
    stored.length === current.length &&
    stored.every((byte, index) => byte === current[index])
  )
}

const registerServiceWorker = async () => {
  const registration = await navigator.serviceWorker.register(
    serviceWorkerUrl,
    { scope: '/' },
  )

  await navigator.serviceWorker.ready

  return registration
}

const readRegistration = async () => {
  if (!('serviceWorker' in navigator)) return null

  return (await navigator.serviceWorker.getRegistration('/')) ?? null
}

const persistSubscription = async (subscription: PushSubscription) => {
  const details = subscription.toJSON()
  const p256dh = details.keys?.p256dh
  const auth = details.keys?.auth

  if (!p256dh || !auth) {
    throw new Error('Η συνδρομή της συσκευής δεν περιέχει κλειδιά.')
  }

  const { error } = await supabase.rpc('upsert_my_push_subscription', {
    p_endpoint: subscription.endpoint,
    p_p256dh: p256dh,
    p_auth: auth,
    p_user_agent: navigator.userAgent.slice(0, 400),
  })

  if (error) {
    throw new Error(error.message)
  }
}

export const getPushStatus = async (): Promise<PushStatus> => {
  const availability = readPushAvailability()
  const permission = readPermission()

  if (availability !== 'ready') {
    return { availability, permission, subscribed: false }
  }

  // Re-registering on load lets an updated worker take over, but it never
  // prompts: the permission dialog only opens from enablePush().
  const registration =
    permission === 'granted'
      ? await registerServiceWorker()
      : await readRegistration()

  const subscription = (await registration?.pushManager.getSubscription()) ?? null

  return {
    availability,
    permission,
    subscribed: subscription !== null && matchesCurrentKey(subscription),
  }
}

/**
 * Re-binds this browser's endpoint to the signed-in account, so a device that
 * later hosts another player stops receiving notifications for the first one.
 */
export const syncPushSubscription = async () => {
  if (readPushAvailability() !== 'ready' || readPermission() !== 'granted') {
    return
  }

  const registration = await readRegistration()
  const subscription = (await registration?.pushManager.getSubscription()) ?? null

  if (!subscription || !matchesCurrentKey(subscription)) return

  await persistSubscription(subscription)
}

export const enablePush = async (): Promise<PushStatus> => {
  const availability = readPushAvailability()

  if (availability !== 'ready') {
    return { availability, permission: readPermission(), subscribed: false }
  }

  const permission = await Notification.requestPermission()

  if (permission !== 'granted') {
    return {
      availability,
      permission: permission === 'denied' ? 'denied' : 'default',
      subscribed: false,
    }
  }

  const registration = await registerServiceWorker()
  let subscription = await registration.pushManager.getSubscription()

  if (subscription && !matchesCurrentKey(subscription)) {
    await subscription.unsubscribe()
    subscription = null
  }

  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: toApplicationServerKey(vapidPublicKey),
    })
  }

  await persistSubscription(subscription)

  return { availability, permission: 'granted', subscribed: true }
}

export const disablePush = async (): Promise<PushStatus> => {
  const availability = readPushAvailability()
  const registration = await readRegistration()
  const subscription = (await registration?.pushManager.getSubscription()) ?? null

  if (subscription) {
    const { error } = await supabase.rpc('delete_my_push_subscription', {
      p_endpoint: subscription.endpoint,
    })

    if (error) {
      throw new Error(error.message)
    }

    await subscription.unsubscribe()
  }

  return { availability, permission: readPermission(), subscribed: false }
}
