export const previewAnnouncementBody = (body: string, limit = 140) => {
  const compact = body.replace(/\s+/g, ' ').trim()

  if (compact.length <= limit) {
    return compact
  }

  return `${compact.slice(0, limit).trimEnd()}…`
}

export const mergeAnnouncementReads = <T extends { id: string }>(
  announcements: T[],
  readIds: Iterable<string>,
) => {
  const reads = new Set(readIds)

  return announcements.map((announcement) => ({
    ...announcement,
    isRead: reads.has(announcement.id),
  }))
}

export const countUnreadAnnouncements = (
  items: Array<{ isRead: boolean }>,
) => items.reduce((total, item) => (item.isRead ? total : total + 1), 0)
