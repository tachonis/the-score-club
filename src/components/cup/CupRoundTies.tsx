import { t } from '../../i18n'
import {
  cupRoundMatchdaySubtitle,
  cupRoundName,
  cupRoundStatusLabel,
  participantsById,
  visibleTiesForRound,
  type PlayersCupSnapshot,
} from '../../lib/cup'
import { formatGreekAllCaps } from '../../lib/greekAllCaps'
import { CupTieCard } from './CupTieCard'

type CupRoundTiesProps = {
  snapshot: PlayersCupSnapshot
  selectedRoundNumber: number
  viewerParticipantId: number | null
}

export function CupRoundTies({
  snapshot,
  selectedRoundNumber,
  viewerParticipantId,
}: CupRoundTiesProps) {
  const round =
    snapshot.rounds.find(
      (item) => item.round_number === selectedRoundNumber,
    ) ?? null
  const matchday = round
    ? snapshot.matchdaysById[round.matchday_id]
    : null
  const ties = round
    ? visibleTiesForRound(snapshot.ties, round.id)
    : []
  const lookup = participantsById(snapshot.participants)

  return (
    <section
      className={`cup-round-section ${
        round?.status === 'in_progress' ? 'is-live' : ''
      }`}
      id={`cup-round-panel-${selectedRoundNumber}`}
      role="tabpanel"
      aria-labelledby={`cup-round-tab-${selectedRoundNumber}`}
    >
      <header className="cup-round-heading">
        <div>
          <p className="dashboard-eyebrow">
            {formatGreekAllCaps(
              cupRoundMatchdaySubtitle(selectedRoundNumber, matchday),
            )}
          </p>
          <h2>{cupRoundName(selectedRoundNumber)}</h2>
        </div>
        {round ? (
          <span className="matchday-status">
            {cupRoundStatusLabel(round.status)}
          </span>
        ) : (
          <span className="matchday-status">{t('cup.statusWaiting')}</span>
        )}
      </header>

      {ties.length === 0 ? (
        <div className="empty-state cup-round-empty">
          <p>
            {t('cup.roundNotReady')}
          </p>
        </div>
      ) : (
        <div className="cup-round-ties">
          {ties.map((tie) => (
            <CupTieCard
              key={tie.id}
              tie={tie}
              participants={lookup}
              viewerParticipantId={viewerParticipantId}
              roundStatus={round?.status ?? 'pending'}
            />
          ))}
        </div>
      )}
    </section>
  )
}
