export type LockablePredictionMatch = {
  id: number
  status: string
  kickoff_at: string
}

/**
 * Existing predictions lock: local save-race lock, non-scheduled status,
 * or kickoff time reached. Callers must pass the same clock and lock set
 * the page already uses.
 */
export const isPredictionMatchLocked = (
  match: LockablePredictionMatch,
  at: number,
  locallyLockedMatchIds: ReadonlySet<number>,
) =>
  locallyLockedMatchIds.has(match.id) ||
  match.status !== 'scheduled' ||
  at >= new Date(match.kickoff_at).getTime()
