import { t } from '../../i18n'
import {
  cupRoundName,
  decidedByRuleLabel,
  findViewerParticipant,
  nextRoundName,
  participantsById,
  selectPersonalTie,
  type CupParticipant,
  type PlayersCupSnapshot,
} from '../../lib/cup'
import { formatGreekAllCaps } from '../../lib/greekAllCaps'
import { CupPlayerName } from './CupTieCard'

type CupPersonalTieCardProps = {
  snapshot: PlayersCupSnapshot
  selectedRoundNumber: number
}

export function CupPersonalTieCard({
  snapshot,
  selectedRoundNumber,
}: CupPersonalTieCardProps) {
  const viewerParticipant = findViewerParticipant(
    snapshot.participants,
    snapshot.viewerUserId,
  )

  if (!viewerParticipant) {
    return (
      <article className="cup-personal-card">
        <p className="dashboard-eyebrow">
          {formatGreekAllCaps(t('cup.yourTie'))}
        </p>
        <h2>{t('cup.notInCup')}</h2>
        <p>{t('cup.watchBelow')}</p>
      </article>
    )
  }

  const lookup = participantsById(snapshot.participants)
  const selectedRound =
    snapshot.rounds.find(
      (round) => round.round_number === selectedRoundNumber,
    ) ?? null
  const tie = selectPersonalTie(
    viewerParticipant.id,
    selectedRound?.id ?? null,
    snapshot.rounds,
    snapshot.ties,
  )

  if (!tie) {
    return (
      <article className="cup-personal-card">
        <p className="dashboard-eyebrow">
          {formatGreekAllCaps(t('cup.yourTie'))}
        </p>
        <h2>{t('cup.slotUnavailable')}</h2>
      </article>
    )
  }

  const tieRound = snapshot.rounds.find((round) => round.id === tie.round_id)
  const tieRoundNumber = tieRound?.round_number ?? selectedRoundNumber
  const upcomingRound = nextRoundName(tieRoundNumber)
  const isFinal = tieRoundNumber === 6
  const home = tie.home_participant_id
    ? lookup.get(tie.home_participant_id)
    : undefined
  const away = tie.away_participant_id
    ? lookup.get(tie.away_participant_id)
    : undefined

  if (tie.outcome === 'bye') {
    const byeId =
      tie.winner_participant_id ??
      tie.home_participant_id ??
      tie.away_participant_id
    const byeParticipant =
      (byeId !== null ? lookup.get(byeId) : undefined) ?? viewerParticipant

    return (
      <article className="cup-personal-card">
        <div className="cup-personal-heading">
          <p className="dashboard-eyebrow">
          {formatGreekAllCaps(t('cup.yourTie'))}
        </p>
          <span className="cup-tie-badge">BYE</span>
        </div>
        <CupPlayerName participant={byeParticipant} isMe />
        <h2>{t('cup.byeAdvance')}</h2>
        {upcomingRound ? (
          <p>{t('cup.advanceTo', { round: upcomingRound })}</p>
        ) : null}
      </article>
    )
  }

  const homeKnown = tie.home_participant_id !== null
  const awayKnown = tie.away_participant_id !== null

  if (tie.outcome === 'pending' && homeKnown !== awayKnown) {
    const known = homeKnown ? home : away
    const knownId = homeKnown
      ? tie.home_participant_id
      : tie.away_participant_id

    return (
      <article className="cup-personal-card">
        <div className="cup-personal-heading">
          <p className="dashboard-eyebrow">
          {formatGreekAllCaps(t('cup.yourTie'))}
        </p>
          <span className="cup-tie-badge is-waiting">{t('cup.statusWaiting')}</span>
        </div>
        <h2>{cupRoundName(tieRoundNumber)}</h2>
        <div className="cup-tie-sides">
          <div className="cup-tie-side">
            <CupPlayerName
              participant={known}
              isMe={knownId === viewerParticipant.id}
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
      <article className="cup-personal-card">
        <div className="cup-personal-heading">
          <p className="dashboard-eyebrow">
          {formatGreekAllCaps(t('cup.yourTie'))}
        </p>
          <span className="cup-tie-badge is-live">{t('cup.statusLive')}</span>
        </div>
        <h2>{cupRoundName(tieRoundNumber)}</h2>
        <div className="cup-tie-sides">
          <PersonalScoreRow
            participant={home}
            points={tie.home_points}
            isMe={tie.home_participant_id === viewerParticipant.id}
          />
          <PersonalScoreRow
            participant={away}
            points={tie.away_points}
            isMe={tie.away_participant_id === viewerParticipant.id}
          />
        </div>
      </article>
    )
  }

  const viewerWon = tie.winner_participant_id === viewerParticipant.id
  const statusLabel = isFinal
    ? viewerWon
      ? t('cup.champion')
      : t('cup.finalist')
    : viewerWon
      ? t('cup.advanced')
      : t('cup.eliminated')
  const tieBreak = decidedByRuleLabel(tie.decided_by_rule)

  return (
    <article className="cup-personal-card is-decided">
      <div className="cup-personal-heading">
        <p className="dashboard-eyebrow">
          {formatGreekAllCaps(t('cup.yourTie'))}
        </p>
        <span
          className={`cup-tie-badge ${viewerWon ? 'is-won' : 'is-lost'}`}
        >
          {statusLabel}
        </span>
      </div>
      <h2>{cupRoundName(tieRoundNumber)}</h2>
      <div className="cup-tie-sides">
        <PersonalScoreRow
          participant={home}
          points={tie.home_points}
          isWinner={tie.winner_participant_id === tie.home_participant_id}
          isLoser={tie.winner_participant_id !== tie.home_participant_id}
          isMe={tie.home_participant_id === viewerParticipant.id}
        />
        <PersonalScoreRow
          participant={away}
          points={tie.away_points}
          isWinner={tie.winner_participant_id === tie.away_participant_id}
          isLoser={tie.winner_participant_id !== tie.away_participant_id}
          isMe={tie.away_participant_id === viewerParticipant.id}
        />
      </div>
      {viewerWon && !isFinal && upcomingRound ? (
        <p>{t('cup.nextRound', { round: upcomingRound })}</p>
      ) : null}
      {tieBreak ? <p className="cup-tie-break">{tieBreak}</p> : null}
    </article>
  )
}

function PersonalScoreRow({
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
