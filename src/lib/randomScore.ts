/** Max goals per side for generated football scores (inclusive). */
export const RANDOM_FOOTBALL_MAX_GOALS = 5

type WeightedGoals = {
  goals: number
  weight: number
}

/**
 * Neutral Champions League–style goal counts.
 * Independent home/away draws; no team strength or odds.
 */
export const FOOTBALL_GOAL_WEIGHTS: readonly WeightedGoals[] = [
  { goals: 0, weight: 18 },
  { goals: 1, weight: 28 },
  { goals: 2, weight: 26 },
  { goals: 3, weight: 16 },
  { goals: 4, weight: 8 },
  { goals: 5, weight: 3 },
] as const

export type FootballScore = {
  home: number
  away: number
}

export type RandomSource = () => number

const defaultRandom: RandomSource = () => Math.random()

export const pickWeighted = <T extends { weight: number }>(
  items: readonly T[],
  random: RandomSource = defaultRandom,
): T => {
  if (items.length === 0) {
    throw new Error('pickWeighted requires at least one item')
  }

  const totalWeight = items.reduce((sum, item) => sum + item.weight, 0)

  if (!(totalWeight > 0)) {
    throw new Error('pickWeighted requires a positive total weight')
  }

  let ticket = random() * totalWeight

  for (const item of items) {
    ticket -= item.weight

    if (ticket < 0) {
      return item
    }
  }

  return items[items.length - 1]
}

const pickGoalCount = (random: RandomSource) =>
  pickWeighted(FOOTBALL_GOAL_WEIGHTS, random).goals

/**
 * Returns a realistic football score for draft predictions.
 * Bounds: 0 … RANDOM_FOOTBALL_MAX_GOALS per side.
 */
export const generateRandomFootballScore = (
  random: RandomSource = defaultRandom,
): FootballScore => ({
  home: pickGoalCount(random),
  away: pickGoalCount(random),
})
