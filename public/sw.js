/*
 * The Score Club push worker.
 * Push delivery only: no fetch handler and no cached assets, so the app is
 * always served fresh from the network.
 */

const DEFAULT_DESTINATION = 'predictions'

const ALLOWED_DESTINATIONS = [
  'home',
  'predictions',
  'standings',
  'league-phase',
  'rules',
  'announcements',
]

const ANNOUNCEMENT_ID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const ANNOUNCEMENT_DESTINATION =
  /^announcements(?:\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}))?$/i

const DEFAULT_TITLE = 'The Score Club'

const readAnnouncementDestination = (value) => {
  if (typeof value !== 'string') return null

  const match = value
    .replace(/^#/, '')
    .replace(/^\/+/, '')
    .trim()
    .match(ANNOUNCEMENT_DESTINATION)

  if (!match) return null

  return match[1]
    ? `announcements/${match[1].toLowerCase()}`
    : 'announcements'
}

const readDestination = (value) => {
  const announcement = readAnnouncementDestination(value)

  if (announcement) return announcement

  return ALLOWED_DESTINATIONS.includes(value) ? value : DEFAULT_DESTINATION
}

const readPayload = (event) => {
  if (!event.data) {
    return { title: DEFAULT_TITLE, body: '', destination: DEFAULT_DESTINATION }
  }

  let payload = null

  try {
    payload = event.data.json()
  } catch {
    payload = { body: event.data.text() }
  }

  const announcementId =
    typeof payload?.announcement_id === 'string' &&
    ANNOUNCEMENT_ID.test(payload.announcement_id)
      ? payload.announcement_id.toLowerCase()
      : null

  const fromUrl = readAnnouncementDestination(payload?.url)
  const destination = announcementId
    ? `announcements/${announcementId}`
    : readDestination(fromUrl ?? payload?.destination)

  return {
    title:
      typeof payload?.title === 'string' && payload.title.trim() !== ''
        ? payload.title
        : DEFAULT_TITLE,
    body: typeof payload?.body === 'string' ? payload.body : '',
    destination,
    announcementId: announcementId ?? destination.match(ANNOUNCEMENT_DESTINATION)?.[1] ?? null,
  }
}

self.addEventListener('install', () => {
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('push', (event) => {
  const payload = readPayload(event)

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      tag: payload.announcementId
        ? `the-score-club-announcement-${payload.announcementId}`
        : 'the-score-club-broadcast',
      renotify: true,
      data: {
        destination: payload.destination,
        announcement_id: payload.announcementId,
        url: payload.announcementId
          ? `/announcements/${payload.announcementId}`
          : `/${payload.destination}`,
      },
    }),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()

  const data = event.notification.data ?? {}
  const destination = readDestination(data.destination)
  const targetUrl = new URL(`/#${destination}`, self.location.origin).href

  event.waitUntil(
    (async () => {
      const windowClients = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      })

      for (const client of windowClients) {
        if (new URL(client.url).origin !== self.location.origin) continue

        let targetClient = client

        // Existing PWA windows are often still at start_url `/`. Updating the
        // URL before focus keeps the hash if postMessage arrives before JS.
        if (typeof client.navigate === 'function') {
          try {
            const navigated = await client.navigate(targetUrl)

            if (navigated) {
              targetClient = navigated
            }
          } catch {
            targetClient = client
          }
        }

        await targetClient.focus()
        targetClient.postMessage({
          type: 'push-navigate',
          destination,
          announcement_id: data.announcement_id ?? null,
          url: data.url ?? null,
        })
        return
      }

      await self.clients.openWindow(targetUrl)
    })(),
  )
})
