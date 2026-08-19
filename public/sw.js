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
]

const DEFAULT_TITLE = 'The Score Club'

const readDestination = (value) =>
  ALLOWED_DESTINATIONS.includes(value) ? value : DEFAULT_DESTINATION

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

  return {
    title:
      typeof payload?.title === 'string' && payload.title.trim() !== ''
        ? payload.title
        : DEFAULT_TITLE,
    body: typeof payload?.body === 'string' ? payload.body : '',
    destination: readDestination(payload?.destination),
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
      tag: 'the-score-club-broadcast',
      renotify: true,
      data: { destination: payload.destination },
    }),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()

  const destination = readDestination(event.notification.data?.destination)
  const targetUrl = new URL(`/#${destination}`, self.location.origin).href

  event.waitUntil(
    (async () => {
      const windowClients = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      })

      for (const client of windowClients) {
        if (new URL(client.url).origin !== self.location.origin) continue

        await client.focus()
        client.postMessage({ type: 'push-navigate', destination })
        return
      }

      await self.clients.openWindow(targetUrl)
    })(),
  )
})
