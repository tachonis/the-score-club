import { supabase } from './supabase'
import { mergeAnnouncementReads } from './announcementState'

export {
  countUnreadAnnouncements,
  mergeAnnouncementReads,
  previewAnnouncementBody,
} from './announcementState'

export const announcementCategories = [
  'general',
  'matchday',
  'cup',
  'rules',
] as const

export type AnnouncementCategory = (typeof announcementCategories)[number]

export type Announcement = {
  id: string
  title: string
  body: string
  category: AnnouncementCategory | null
  created_at: string
  published_at: string | null
  created_by: string | null
  is_published: boolean
}

export type AnnouncementListItem = Announcement & {
  isRead: boolean
}

const titleLimit = 120
const bodyLimit = 8000

const countListeners = new Set<() => void>()

export const announcementTitleLimit = titleLimit
export const announcementBodyLimit = bodyLimit

export const isAnnouncementCategory = (
  value: string,
): value is AnnouncementCategory =>
  (announcementCategories as readonly string[]).includes(value)

export const notifyAnnouncementCountChanged = () => {
  countListeners.forEach((listener) => listener())
}

export const subscribeAnnouncementCountRefresh = (listener: () => void) => {
  countListeners.add(listener)

  return () => {
    countListeners.delete(listener)
  }
}

const asAnnouncement = (row: unknown): Announcement => {
  const value = row as Announcement

  return {
    ...value,
    category: isAnnouncementCategory(value.category ?? '')
      ? value.category
      : null,
  }
}

export const loadPublishedAnnouncements = async () => {
  const [{ data, error }, reads] = await Promise.all([
    supabase
      .from('announcements')
      .select(
        'id, title, body, category, created_at, published_at, created_by, is_published',
      )
      .eq('is_published', true)
      .order('published_at', { ascending: false }),
    supabase.from('announcement_reads').select('announcement_id'),
  ])

  if (error) {
    throw new Error(error.message)
  }

  if (reads.error) {
    throw new Error(reads.error.message)
  }

  const readIds = (reads.data ?? []).map(
    (row) => (row as { announcement_id: string }).announcement_id,
  )

  return mergeAnnouncementReads((data ?? []).map(asAnnouncement), readIds)
}

export const loadAnnouncementById = async (id: string) => {
  const [{ data, error }, reads] = await Promise.all([
    supabase
      .from('announcements')
      .select(
        'id, title, body, category, created_at, published_at, created_by, is_published',
      )
      .eq('id', id)
      .maybeSingle(),
    supabase
      .from('announcement_reads')
      .select('announcement_id')
      .eq('announcement_id', id)
      .maybeSingle(),
  ])

  if (error) {
    throw new Error(error.message)
  }

  if (reads.error) {
    throw new Error(reads.error.message)
  }

  if (!data) {
    return null
  }

  return mergeAnnouncementReads(
    [asAnnouncement(data)],
    reads.data ? [reads.data.announcement_id] : [],
  )[0]
}

export const loadAdminAnnouncements = async () => {
  const { data, error } = await supabase
    .from('announcements')
    .select(
      'id, title, body, category, created_at, published_at, created_by, is_published',
    )
    .order('created_at', { ascending: false })

  if (error) {
    throw new Error(error.message)
  }

  return (data ?? []).map(asAnnouncement)
}

export const loadUnreadAnnouncementCount = async () => {
  const { data, error } = await supabase.rpc('count_unread_announcements')

  if (error) {
    throw new Error(error.message)
  }

  return typeof data === 'number' ? data : 0
}

export const markAnnouncementRead = async (id: string) => {
  const { error } = await supabase.rpc('mark_announcement_read', {
    p_announcement_id: id,
  })

  if (error) {
    throw new Error(error.message)
  }

  notifyAnnouncementCountChanged()
}

export const saveAnnouncement = async (input: {
  id?: string
  title: string
  body: string
  category: AnnouncementCategory | ''
  isPublished: boolean
  createdBy?: string | null
}) => {
  const payload = {
    title: input.title.trim(),
    body: input.body.trim(),
    category: input.category === '' ? null : input.category,
    is_published: input.isPublished,
    ...(input.id ? {} : { created_by: input.createdBy ?? null }),
  }

  const query = input.id
    ? supabase.from('announcements').update(payload).eq('id', input.id)
    : supabase.from('announcements').insert(payload)

  const { error } = await query

  if (error) {
    throw new Error(error.message)
  }
}

export const deleteAnnouncement = async (id: string) => {
  const { error } = await supabase.from('announcements').delete().eq('id', id)

  if (error) {
    throw new Error(error.message)
  }
}
