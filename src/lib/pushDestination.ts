export const ANNOUNCEMENT_PAGE = 'announcements'

export const ANNOUNCEMENT_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export const ANNOUNCEMENT_DETAIL_PATTERN =
  /^announcements\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i

export const pagePushDestinations = [
  'home',
  'predictions',
  'standings',
  'players-cup',
  'league-phase',
  'rules',
  ANNOUNCEMENT_PAGE,
] as const

export type PagePushDestination = (typeof pagePushDestinations)[number]

export type PushTarget = {
  destination: PagePushDestination
  announcementId: string | null
}

const isPagePushDestination = (value: string): value is PagePushDestination =>
  (pagePushDestinations as readonly string[]).includes(value)

const normalizeDestination = (raw: string) =>
  raw.replace(/^#/, '').replace(/^\/+/, '').trim()

export const parsePushTarget = (raw: string): PushTarget | null => {
  const value = normalizeDestination(raw)

  if (value === '') {
    return null
  }

  const detail = value.match(ANNOUNCEMENT_DETAIL_PATTERN)

  if (detail) {
    return {
      destination: ANNOUNCEMENT_PAGE,
      announcementId: detail[1].toLowerCase(),
    }
  }

  if (!isPagePushDestination(value)) {
    return null
  }

  return {
    destination: value,
    announcementId: null,
  }
}

export const announcementPushDestination = (id: string) =>
  `${ANNOUNCEMENT_PAGE}/${id}`

export const announcementPath = (id?: string | null) =>
  id ? `/${ANNOUNCEMENT_PAGE}/${id}` : `/${ANNOUNCEMENT_PAGE}`

export const isAllowedBroadcastDestination = (value: string) => {
  if (
    value === 'home' ||
    value === 'predictions' ||
    value === 'standings' ||
    value === 'league-phase' ||
    value === 'rules' ||
    value === ANNOUNCEMENT_PAGE
  ) {
    return true
  }

  return ANNOUNCEMENT_DETAIL_PATTERN.test(value)
}

export const resolveNotificationClickTarget = (payload: {
  destination?: unknown
  announcement_id?: unknown
  url?: unknown
}) => {
  if (
    typeof payload.announcement_id === 'string' &&
    ANNOUNCEMENT_ID_PATTERN.test(payload.announcement_id)
  ) {
    const id = payload.announcement_id.toLowerCase()

    return {
      destination: announcementPushDestination(id),
      url: announcementPath(id),
    }
  }

  if (typeof payload.destination === 'string') {
    const target = parsePushTarget(payload.destination)

    if (target) {
      return {
        destination: target.announcementId
          ? announcementPushDestination(target.announcementId)
          : target.destination,
        url: target.announcementId
          ? announcementPath(target.announcementId)
          : `/${target.destination}`,
      }
    }
  }

  if (typeof payload.url === 'string') {
    const target = parsePushTarget(payload.url)

    if (target) {
      return {
        destination: target.announcementId
          ? announcementPushDestination(target.announcementId)
          : target.destination,
        url: target.announcementId
          ? announcementPath(target.announcementId)
          : `/${target.destination}`,
      }
    }
  }

  return null
}
