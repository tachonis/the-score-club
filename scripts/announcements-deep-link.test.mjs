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

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relativePath) =>
  readFileSync(path.join(root, relativePath), 'utf8')

const announcementId = 'c0a11e11-0a11-4e11-8c01-000000000001'

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
  assert.match(source, /client\.focus\(\)/)
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
