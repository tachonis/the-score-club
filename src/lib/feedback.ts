import { supabase } from './supabase'

export const feedbackCategories = [
  'bug',
  'account',
  'suggestion',
  'other',
] as const

export type FeedbackCategory = (typeof feedbackCategories)[number]

export type FeedbackStatus = 'new' | 'read' | 'resolved'

export type FeedbackInboxRow = {
  id: string
  user_id: string
  username: string
  email: string | null
  category: FeedbackCategory
  message: string
  status: FeedbackStatus
  created_at: string
  updated_at: string
  resolved_at: string | null
}

const messageLimit = 1000

const countListeners = new Set<() => void>()

export const feedbackMessageLimit = messageLimit

export const isFeedbackCategory = (
  value: string,
): value is FeedbackCategory =>
  (feedbackCategories as readonly string[]).includes(value)

export const notifyFeedbackCountChanged = () => {
  countListeners.forEach((listener) => listener())
}

export const subscribeFeedbackCountRefresh = (listener: () => void) => {
  countListeners.add(listener)

  return () => {
    countListeners.delete(listener)
  }
}

export const submitFeedback = async (
  category: FeedbackCategory,
  message: string,
) => {
  const { error } = await supabase.rpc('submit_feedback', {
    p_category: category,
    p_message: message,
  })

  if (error) {
    throw new Error(error.message)
  }

  notifyFeedbackCountChanged()
}

export const loadFeedbackInbox = async () => {
  const { data, error } = await supabase.rpc('get_feedback_messages')

  if (error) {
    throw new Error(error.message)
  }

  return (data ?? []) as FeedbackInboxRow[]
}

export const loadNewFeedbackCount = async () => {
  const { data, error } = await supabase.rpc('count_new_feedback_messages')

  if (error) {
    throw new Error(error.message)
  }

  return typeof data === 'number' ? data : 0
}

export const setFeedbackStatus = async (
  id: string,
  status: FeedbackStatus,
) => {
  const { error } = await supabase.rpc('set_feedback_status', {
    p_id: id,
    p_status: status,
  })

  if (error) {
    throw new Error(error.message)
  }

  notifyFeedbackCountChanged()
}
