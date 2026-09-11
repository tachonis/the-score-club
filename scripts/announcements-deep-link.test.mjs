import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import {
  countUnreadAnnouncements,
  mergeAnnouncementReads,
} from '../src/lib/announcementState.ts'
import {
  isAllowedBroadcastDestination,
  parsePushTarget,
  resolveNotificationClickTarget,
} from '../src/lib/pushDestination.ts'
import {
  canApplyPendingPushTarget,
  captureLocationPushTarget,
  clearConsumedPushHash,
  consumePendingPushTarget,
  parsePushNavigateMessage,
  peekPendingPushTarget,
  rememberPushTarget,
  resolveVisiblePushRoute,
} from '../src/lib/pushNavigation.ts'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relativePath) =>
  readFileSync(path.join(root, relativePath), 'utf8')

const announcementId = 'c0a11e11-0a11-4e11-8c01-000000000001'
const announcementTarget = {
  destination: 'announcements',
  announcementId,
}

const memoryStorage = () => {
  const values = new Map()

  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => {
      values.set(key, value)
    },
    removeItem: (key) => {
      values.delete(key)
    },
  }
}

test('existing page destinations still resolve', () => {
  for (const page of [
    'home',
    'predictions',
    'standings',
    'players-cup',
    'league-phase',
    'rules',
  ]) {
    assert.deepEqual(parsePushTarget(`#${page}`), {
      destination: page,
      announcementId: null,
    })
    assert.equal(isAllowedBroadcastDestination(page), page !== 'players-cup')
  }
})

test('announcement list and detail deep links resolve', () => {
  assert.deepEqual(parsePushTarget('#announcements'), {
    destination: 'announcements',
    announcementId: null,
  })
  assert.deepEqual(parsePushTarget(`/announcements/${announcementId}`), {
    destination: 'announcements',
    announcementId,
  })
  assert.deepEqual(parsePushTarget(`#announcements/${announcementId}`), {
    destination: 'announcements',
    announcementId,
  })
})

test('unknown destinations are rejected', () => {
  assert.equal(parsePushTarget('#admin'), null)
  assert.equal(parsePushTarget('/not-a-page'), null)
  assert.equal(parsePushTarget('announcements/not-a-uuid'), null)
})

test('announcement push contains announcement id and url', () => {
  const fromDestination = resolveNotificationClickTarget({
    destination: `announcements/${announcementId}`,
  })
  const fromId = resolveNotificationClickTarget({
    destination: 'predictions',
    announcement_id: announcementId,
  })

  assert.deepEqual(fromDestination, {
    destination: `announcements/${announcementId}`,
    url: `/announcements/${announcementId}`,
  })
  assert.deepEqual(fromId, {
    destination: `announcements/${announcementId}`,
    url: `/announcements/${announcementId}`,
  })
})

test('existing push types still resolve to their own route', () => {
  const target = resolveNotificationClickTarget({
    destination: 'predictions',
  })

  assert.deepEqual(target, {
    destination: 'predictions',
    url: '/predictions',
  })
  assert.equal(isAllowedBroadcastDestination('predictions'), true)
  assert.equal(
    isAllowedBroadcastDestination(`announcements/${announcementId}`),
    true,
  )
})

test('unread tracking is idempotent and decreases the count', () => {
  const announcements = [
    { id: 'a' },
    { id: 'b' },
    { id: 'c' },
  ]
  const unread = mergeAnnouncementReads(announcements, [])
  assert.equal(countUnreadAnnouncements(unread), 3)

  const afterOpen = mergeAnnouncementReads(announcements, ['a'])
  assert.equal(countUnreadAnnouncements(afterOpen), 2)

  const reopened = mergeAnnouncementReads(announcements, ['a', 'a'])
  assert.equal(countUnreadAnnouncements(reopened), 2)
  assert.equal(reopened.filter((item) => item.id === 'a' && item.isRead).length, 1)
})

test('service worker still handles existing destinations and announcement clicks', () => {
  const source = read('public/sw.js')

  for (const destination of [
    'home',
    'predictions',
    'standings',
    'league-phase',
    'rules',
  ]) {
    assert.match(source, new RegExp(`'${destination}'`))
  }

  assert.match(source, /announcements/)
  assert.match(source, /announcement_id/)
  assert.match(source, /\/#\$\{destination\}/)
  assert.match(source, /type: 'push-navigate'/)
  assert.match(source, /clients\.openWindow/)
  assert.match(source, /targetClient\.focus\(\)/)
  assert.match(source, /client\.navigate/)
})

test('broadcast sender keeps existing destinations and adds announcement ids', () => {
  const source = read('supabase/functions/send-broadcast-push/index.ts')

  for (const destination of [
    'home',
    'predictions',
    'standings',
    'league-phase',
    'rules',
  ]) {
    assert.match(source, new RegExp(`'${destination}'`))
  }

  assert.match(source, /announcement_id/)
  assert.match(source, /\/announcements\/\$\{announcementId\}/)
})

test('initial hash #announcements/{uuid} resolves to announcement detail', () => {
  const storage = memoryStorage()
  const target = captureLocationPushTarget(
    { hash: `#announcements/${announcementId}`, pathname: '/' },
    storage,
  )

  assert.deepEqual(target, announcementTarget)
  assert.deepEqual(
    resolveVisiblePushRoute({
      pending: target,
      appPage: 'home',
      announcementId: null,
    }),
    announcementTarget,
  )
})

test('hash destination survives app initialization and auth restoration', () => {
  const storage = memoryStorage()

  captureLocationPushTarget(
    { hash: `#announcements/${announcementId}`, pathname: '/' },
    storage,
  )

  assert.equal(
    canApplyPendingPushTarget({
      hasSession: false,
      hasProfile: false,
      passwordRecovery: false,
    }),
    false,
  )

  // Auth bootstrap may strip the hash before the app is ready.
  captureLocationPushTarget({ hash: '', pathname: '/' }, storage)

  assert.deepEqual(peekPendingPushTarget(storage), announcementTarget)
  assert.equal(
    canApplyPendingPushTarget({
      hasSession: true,
      hasProfile: true,
      passwordRecovery: false,
    }),
    true,
  )

  const applied = consumePendingPushTarget(storage)
  const history = { url: `/#announcements/${announcementId}` }

  clearConsumedPushHash(
    {
      hash: `#announcements/${announcementId}`,
      pathname: '/',
      search: '',
    },
    {
      replaceState(_state, _unused, url) {
        history.url = url
      },
    },
  )

  assert.deepEqual(applied, announcementTarget)
  assert.equal(peekPendingPushTarget(storage), null)
  assert.equal(history.url, '/')
  assert.deepEqual(
    resolveVisiblePushRoute({
      pending: null,
      appPage: applied.destination,
      announcementId: applied.announcementId,
    }),
    announcementTarget,
  )
})

test('existing-client push-navigate opens announcement detail', () => {
  const storage = memoryStorage()
  const fromMessage = parsePushNavigateMessage({
    type: 'push-navigate',
    destination: `announcements/${announcementId}`,
    announcement_id: announcementId,
    url: `/announcements/${announcementId}`,
  })

  rememberPushTarget(fromMessage, storage)

  assert.deepEqual(
    resolveVisiblePushRoute({
      pending: peekPendingPushTarget(storage),
      appPage: 'home',
      announcementId: null,
    }),
    announcementTarget,
  )
})

test('push-navigate before app ready stays pending then opens detail', () => {
  const storage = memoryStorage()
  const fromMessage = parsePushNavigateMessage({
    type: 'push-navigate',
    destination: `announcements/${announcementId}`,
  })

  rememberPushTarget(fromMessage, storage)

  assert.equal(
    canApplyPendingPushTarget({
      hasSession: true,
      hasProfile: false,
      passwordRecovery: false,
    }),
    false,
  )
  assert.deepEqual(peekPendingPushTarget(storage), announcementTarget)

  assert.equal(
    canApplyPendingPushTarget({
      hasSession: true,
      hasProfile: true,
      passwordRecovery: false,
    }),
    true,
  )

  const applied = consumePendingPushTarget(storage)

  assert.deepEqual(applied, announcementTarget)
  assert.equal(peekPendingPushTarget(storage), null)
  assert.deepEqual(
    resolveVisiblePushRoute({
      pending: null,
      appPage: 'home',
      announcementId: null,
    }),
    { destination: 'home', announcementId: null },
  )
  assert.deepEqual(
    resolveVisiblePushRoute({
      pending: null,
      appPage: applied.destination,
      announcementId: applied.announcementId,
    }),
    announcementTarget,
  )
})

test('home destination still works after pending navigation', () => {
  const storage = memoryStorage()
  const target = captureLocationPushTarget(
    { hash: '#home', pathname: '/' },
    storage,
  )

  assert.deepEqual(target, { destination: 'home', announcementId: null })
  assert.deepEqual(
    resolveVisiblePushRoute({
      pending: consumePendingPushTarget(storage),
      appPage: 'announcements',
      announcementId,
    }),
    { destination: 'home', announcementId: null },
  )
})

test('predictions destination still works', () => {
  const storage = memoryStorage()
  const target = parsePushNavigateMessage({
    type: 'push-navigate',
    destination: 'predictions',
  })

  rememberPushTarget(target, storage)

  assert.deepEqual(consumePendingPushTarget(storage), {
    destination: 'predictions',
    announcementId: null,
  })
  assert.deepEqual(parsePushTarget('#predictions'), {
    destination: 'predictions',
    announcementId: null,
  })
})

test('standings, league-phase, and rules destinations still work', () => {
  for (const destination of ['standings', 'league-phase', 'rules']) {
    assert.deepEqual(parsePushTarget(`#${destination}`), {
      destination,
      announcementId: null,
    })
    assert.deepEqual(
      parsePushNavigateMessage({
        type: 'push-navigate',
        destination,
      }),
      { destination, announcementId: null },
    )
    assert.equal(isAllowedBroadcastDestination(destination), true)
  }
})

test('malformed announcement UUID uses a safe fallback', () => {
  const storage = memoryStorage()

  assert.equal(parsePushTarget('#announcements/not-a-uuid'), null)
  assert.equal(
    parsePushNavigateMessage({
      type: 'push-navigate',
      destination: 'announcements/not-a-uuid',
      announcement_id: 'not-a-uuid',
      url: '/announcements/not-a-uuid',
    }),
    null,
  )
  assert.equal(
    captureLocationPushTarget(
      { hash: '#announcements/not-a-uuid', pathname: '/' },
      storage,
    ),
    null,
  )
  assert.equal(peekPendingPushTarget(storage), null)
  assert.deepEqual(
    resolveVisiblePushRoute({
      pending: null,
      appPage: 'home',
      announcementId: null,
    }),
    { destination: 'home', announcementId: null },
  )
})

test('external and arbitrary destinations remain rejected', () => {
  assert.equal(parsePushTarget('https://evil.example/phish'), null)
  assert.equal(parsePushTarget('#admin'), null)
  assert.equal(isAllowedBroadcastDestination('https://evil.example'), false)
  assert.equal(
    isAllowedBroadcastDestination('/announcements/../../../etc/passwd'),
    false,
  )
  assert.equal(
    parsePushNavigateMessage({
      type: 'push-navigate',
      destination: 'https://evil.example',
      url: 'https://evil.example/phish',
    }),
    null,
  )
})
