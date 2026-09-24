import {
  generateRandomFootballScore,
  type RandomSource,
} from './randomScore.ts'

export type ScoreDraft = {
  home: string
  away: string
}

const defaultRandom: RandomSource = () => Math.random()

export const isBlankScore = (value: string | null | undefined) =>
  value === undefined || value === null || value === ''

/** Both sides blank. A single filled side is a partial, user-entered draft. */
export const isFullyEmptyPrediction = (
  prediction: { home?: string | null; away?: string | null } | undefined,
) => isBlankScore(prediction?.home) && isBlankScore(prediction?.away)

export const predictionDraftDiffersFromSaved = (
  current: ScoreDraft | undefined,
  saved: ScoreDraft | undefined,
) => {
  const currentHome = current?.home ?? ''
  const currentAway = current?.away ?? ''
  const savedHome = saved?.home ?? ''
  const savedAway = saved?.away ?? ''

  return currentHome !== savedHome || currentAway !== savedAway
}

export const isEligibleForMatchdayRandomise = <T extends { id: number }>(
  match: T,
  predictions: Readonly<Record<number, ScoreDraft | undefined>>,
  isLocked: (match: T) => boolean,
) => !isLocked(match) && isFullyEmptyPrediction(predictions[match.id])

/**
 * One draft update. Fills only fully empty, unlocked matches.
 * Does not mutate the input map and does not touch saved predictions.
 */
export const applyRandomiseMatchdayDraft = <T extends { id: number }>(
  predictions: Readonly<Record<number, ScoreDraft>>,
  matches: readonly T[],
  isLocked: (match: T) => boolean,
  random: RandomSource = defaultRandom,
): { predictions: Record<number, ScoreDraft>; filledCount: number } => {
  const eligible = matches.filter((match) =>
    isEligibleForMatchdayRandomise(match, predictions, isLocked),
  )

  if (eligible.length === 0) {
    return {
      predictions: predictions as Record<number, ScoreDraft>,
      filledCount: 0,
    }
  }

  const next: Record<number, ScoreDraft> = { ...predictions }

  for (const match of eligible) {
    const score = generateRandomFootballScore(random)

    next[match.id] = {
      home: String(score.home),
      away: String(score.away),
    }
  }

  return { predictions: next, filledCount: eligible.length }
}
