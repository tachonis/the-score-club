import { t } from '../../i18n'
import { getExcludedCountForRound, type CupExcludedMatch } from '../../lib/cup'

type CupExcludedNoteProps = {
  excludedMatches: CupExcludedMatch[]
  roundId: number | null
}

export function CupExcludedNote({
  excludedMatches,
  roundId,
}: CupExcludedNoteProps) {
  const count = getExcludedCountForRound(excludedMatches, roundId)

  if (count === 0) {
    return null
  }

  return (
    <p className="cup-excluded-note">
      {count === 1
        ? t('cup.excludedOne')
        : t('cup.excludedMany', { count })}
    </p>
  )
}
