import {
  cupAwardLabel,
  findViewerParticipant,
  getCupHonours,
  participantDisplayName,
  participantsById,
  type CupAward,
  type CupParticipant,
  type PlayersCupSnapshot,
} from '../../lib/cup'
import { formatGreekAllCaps } from '../../lib/greekAllCaps'
import { CupPlayerName } from './CupTieCard'

type CupHonoursProps = {
  snapshot: PlayersCupSnapshot
}

export function CupHonours({ snapshot }: CupHonoursProps) {
  if (snapshot.awards.length === 0) {
    return null
  }

  const lookup = participantsById(snapshot.participants)
  const viewerParticipant = findViewerParticipant(
    snapshot.participants,
    snapshot.viewerUserId,
  )
  const { winner, finalist, semiFinalists } = getCupHonours(snapshot.awards)
  const orderedSemis = [...semiFinalists].sort((left, right) => {
    const byName = participantDisplayName(
      lookup.get(left.participant_id),
    ).localeCompare(
      participantDisplayName(lookup.get(right.participant_id)),
      'el',
    )

    if (byName !== 0) return byName

    return left.participant_id - right.participant_id
  })

  return (
    <section className="cup-honours" aria-labelledby="cup-honours-heading">
      <h2 id="cup-honours-heading">Έπαθλα</h2>

      {winner ? (
        <HonourCard
          award={winner}
          participant={lookup.get(winner.participant_id)}
          viewerParticipantId={viewerParticipant?.id ?? null}
          featured
        />
      ) : null}

      <div className="cup-honours-grid">
        {finalist ? (
          <HonourCard
            award={finalist}
            participant={lookup.get(finalist.participant_id)}
            viewerParticipantId={viewerParticipant?.id ?? null}
          />
        ) : null}
        {orderedSemis.map((award) => (
          <HonourCard
            key={award.id}
            award={award}
            participant={lookup.get(award.participant_id)}
            viewerParticipantId={viewerParticipant?.id ?? null}
          />
        ))}
      </div>
    </section>
  )
}

function HonourCard({
  award,
  participant,
  viewerParticipantId,
  featured = false,
}: {
  award: CupAward
  participant: CupParticipant | undefined
  viewerParticipantId: number | null
  featured?: boolean
}) {
  const isMe =
    viewerParticipantId !== null && award.participant_id === viewerParticipantId

  return (
    <article
      className={`cup-honour-card ${featured ? 'is-featured' : ''} ${
        isMe ? 'is-me' : ''
      }`}
    >
      <p className="dashboard-eyebrow">
        {formatGreekAllCaps(cupAwardLabel(award.award_type))}
      </p>
      {featured ? (
        <h3 className="cup-honour-name">
          <CupPlayerName participant={participant} isMe={isMe} />
        </h3>
      ) : (
        <CupPlayerName participant={participant} isMe={isMe} />
      )}
      <p className="cup-honour-points">+{award.points} βαθμοί</p>
    </article>
  )
}
