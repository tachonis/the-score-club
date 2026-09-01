import { t } from '../../i18n'
import {
  CUP_ROUND_NUMBERS,
  cupRoundName,
} from '../../lib/cup'

type CupRoundStripProps = {
  selectedRoundNumber: number
  onSelect: (roundNumber: number) => void
}

export function CupRoundStrip({
  selectedRoundNumber,
  onSelect,
}: CupRoundStripProps) {
  return (
    <div className="cup-round-selector">
      <div className="cup-round-tabs" role="tablist" aria-label={t('cup.roundsAria')}>
        {CUP_ROUND_NUMBERS.map((roundNumber) => {
          const selected = selectedRoundNumber === roundNumber

          return (
            <button
              key={roundNumber}
              type="button"
              role="tab"
              id={`cup-round-tab-${roundNumber}`}
              className={`cup-round-tab ${selected ? 'active' : ''}`}
              aria-selected={selected}
              aria-controls={`cup-round-panel-${roundNumber}`}
              onClick={() => onSelect(roundNumber)}
            >
              {cupRoundName(roundNumber)}
            </button>
          )
        })}
      </div>
    </div>
  )
}
