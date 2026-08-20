import {
  decidedByRuleLabel,
  isSeededRank,
  participantDisplayName,
  type CupParticipant,
  type CupRoundStatus,
  type CupTie,
} from '../../lib/cup'

type ParticipantMap = Map<number, CupParticipant>

export function CupSeedBadge({ rankPosition }: { rankPosition: number }) {
  if (!isSeededRank(rankPosition)) {
    return null
  }

  return (
    <span className="cup-seed-badge" aria-label={`Seed ${rankPosition}`}>
      S{rankPosition}
    </span>
  )
}

export function CupPlayerName({
  participant,
  isWinner = false,
  isLoser = false,
  isMe = false,
}: {
  participant: CupParticipant | undefined
  isWinner?: boolean
  isLoser?: boolean
  isMe?: boolean
}) {
  const name = participantDisplayName(participant)

  return (
    <span
      className={`cup-player-name ${isWinner ? 'is-winner' : ''} ${
        isLoser ? 'is-loser' : ''
      } ${isMe ? 'is-me' : ''}`}
      title={name}
      aria-label={name}
    >
      <span className="cup-player-name-text">{name}</span>
      {participant ? <CupSeedBadge rankPosition={participant.rank_position} /> : null}
      {isMe ? <span className="cup-me-tag">Εσύ</span> : null}
    </span>
  )
}

const lookupParticipant = (
  participants: ParticipantMap,
  participantId: number | null,
) => (participantId === null ? undefined : participants.get(participantId))

export function CupTieCard({
  tie,
  participants,
  viewerParticipantId,
  roundStatus = 'pending',
}: {
  tie: CupTie
  participants: ParticipantMap
  viewerParticipantId: number | null
  roundStatus?: CupRoundStatus
}) {
  const home = lookupParticipant(participants, tie.home_participant_id)
  const away = lookupParticipant(participants, tie.away_participant_id)
  const viewerIsInTie =
    viewerParticipantId !== null &&
    (tie.home_participant_id === viewerParticipantId ||
      tie.away_participant_id === viewerParticipantId)

  if (tie.outcome === 'bye') {
    const byeParticipant = lookupParticipant(
      participants,
      tie.winner_participant_id ??
        tie.home_participant_id ??
        tie.away_participant_id,
    )

    return (
      <article
        className={`cup-tie-card is-bye ${viewerIsInTie ? 'is-me' : ''}`}
      >
        <div className="cup-tie-card-top">
          <span className="cup-tie-badge">BYE</span>
        </div>
        <CupPlayerName
          participant={byeParticipant}
          isMe={
            viewerParticipantId !== null &&
            byeParticipant?.id === viewerParticipantId
          }
        />
        <p className="cup-tie-copy">Πέρασε χωρίς αγώνα</p>
      </article>
    )
  }

  const homeKnown = tie.home_participant_id !== null
  const awayKnown = tie.away_participant_id !== null

  if (tie.outcome === 'pending' && homeKnown !== awayKnown) {
    const known = homeKnown ? home : away
    const knownId = homeKnown ? tie.home_participant_id : tie.away_participant_id

    return (
      <article
        className={`cup-tie-card is-waiting-opponent ${viewerIsInTie ? 'is-me' : ''}`}
      >
        <div className="cup-tie-card-top">
          <span className="cup-tie-badge is-waiting">Αναμονή</span>
        </div>
        <div className="cup-tie-sides">
          <div className="cup-tie-side">
            <CupPlayerName
              participant={known}
              isMe={
                viewerParticipantId !== null && knownId === viewerParticipantId
              }
            />
          </div>
          <p className="cup-tie-vs">vs</p>
          <div className="cup-tie-side is-waiting-slot">
            <span className="cup-player-name-text">Περιμένει αντίπαλο</span>
          </div>
        </div>
      </article>
    )
  }

  if (tie.outcome === 'pending') {
    return (
      <article
        className={`cup-tie-card is-in-progress ${viewerIsInTie ? 'is-me' : ''}`}
      >
        <div className="cup-tie-card-top">
          <span
            className={`cup-tie-badge ${
              roundStatus === 'in_progress' ? 'is-live' : 'is-waiting'
            }`}
          >
            Σε εξέλιξη
          </span>
        </div>
        <div className="cup-tie-sides">
          <CupScoreRow
            participant={home}
            points={tie.home_points}
            isMe={
              viewerParticipantId !== null &&
              tie.home_participant_id === viewerParticipantId
            }
          />
          <CupScoreRow
            participant={away}
            points={tie.away_points}
            isMe={
              viewerParticipantId !== null &&
              tie.away_participant_id === viewerParticipantId
            }
          />
        </div>
      </article>
    )
  }

  const winnerId = tie.winner_participant_id
  const tieBreak = decidedByRuleLabel(tie.decided_by_rule)

  return (
    <article className={`cup-tie-card is-decided ${viewerIsInTie ? 'is-me' : ''}`}>
      <div className="cup-tie-card-top">
        <span className="cup-tie-badge is-decided">Ολοκληρώθηκε</span>
      </div>
      <div className="cup-tie-sides">
        <CupScoreRow
          participant={home}
          points={tie.home_points}
          isWinner={winnerId === tie.home_participant_id}
          isLoser={winnerId !== null && winnerId !== tie.home_participant_id}
          isMe={
            viewerParticipantId !== null &&
            tie.home_participant_id === viewerParticipantId
          }
        />
        <CupScoreRow
          participant={away}
          points={tie.away_points}
          isWinner={winnerId === tie.away_participant_id}
          isLoser={winnerId !== null && winnerId !== tie.away_participant_id}
          isMe={
            viewerParticipantId !== null &&
            tie.away_participant_id === viewerParticipantId
          }
        />
      </div>
      {tieBreak ? <p className="cup-tie-break">{tieBreak}</p> : null}
    </article>
  )
}

function CupScoreRow({
  participant,
  points,
  isWinner = false,
  isLoser = false,
  isMe = false,
}: {
  participant: CupParticipant | undefined
  points: number
  isWinner?: boolean
  isLoser?: boolean
  isMe?: boolean
}) {
  return (
    <div
      className={`cup-tie-side ${isWinner ? 'is-winner' : ''} ${
        isLoser ? 'is-loser' : ''
      }`}
    >
      <CupPlayerName
        participant={participant}
        isWinner={isWinner}
        isLoser={isLoser}
        isMe={isMe}
      />
      <strong className="cup-tie-score" aria-label={`${points} βαθμοί`}>
        {points}
      </strong>
      {isWinner ? <span className="cup-winner-mark">Νικητής</span> : null}
    </div>
  )
}
