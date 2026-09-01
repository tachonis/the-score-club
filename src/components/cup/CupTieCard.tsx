import { t } from '../../i18n'
import { usePlayerProfileNav } from '../../lib/playerProfileNav'
import {
  decidedByRuleLabel,
  isSeededRank,
  participantDisplayName,
  type CupParticipant,
  type CupRoundStatus,
  type CupTie,
} from '../../lib/cup'
import { formatGreekAllCaps } from '../../lib/greekAllCaps'

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
  const { openProfile } = usePlayerProfileNav()
  const userId = participant?.user_id ?? null
  const className = `cup-player-name ${isWinner ? 'is-winner' : ''} ${
    isLoser ? 'is-loser' : ''
  } ${isMe ? 'is-me' : ''}`
  const content = (
    <>
      <span className="cup-player-name-text">{name}</span>
      {participant ? (
        <CupSeedBadge rankPosition={participant.rank_position} />
      ) : null}
      {isMe ? (
        <span className="cup-me-tag">{formatGreekAllCaps(t('common.you'))}</span>
      ) : null}
    </>
  )

  if (userId) {
    return (
      <button
        type="button"
        className={className}
        title={name}
        aria-label={t('nav.profileOf', { username: name })}
        onClick={() => openProfile(userId)}
      >
        {content}
      </button>
    )
  }

  return (
    <span className={className} title={name} aria-label={name}>
      {content}
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
        <p className="cup-tie-copy">{t('cup.byeAdvance')}</p>
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
          <span className="cup-tie-badge is-waiting">{t('cup.statusWaiting')}</span>
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
            <span className="cup-player-name-text">{t('cup.waitingOpponent')}</span>
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
            {t('cup.statusLive')}
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
        <span className="cup-tie-badge is-decided">{t('cup.statusDone')}</span>
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
      <strong className="cup-tie-score" aria-label={t('cup.points', { n: points })}>
        {points}
      </strong>
      {isWinner ? (
        <span className="cup-winner-mark">{formatGreekAllCaps(t('cup.winner'))}</span>
      ) : null}
    </div>
  )
}
