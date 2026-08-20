import {
  cupRoundMatchdaySubtitle,
  cupRoundName,
  decidedByRuleLabel,
  findViewerParticipant,
  getViewerCupPath,
  participantDisplayName,
  participantsById,
  type CupParticipant,
  type CupPathRow,
  type CupTie,
  type PlayersCupSnapshot,
} from '../../lib/cup'

type CupPersonalPathProps = {
  snapshot: PlayersCupSnapshot
}

export function CupPersonalPath({ snapshot }: CupPersonalPathProps) {
  const viewerParticipant = findViewerParticipant(
    snapshot.participants,
    snapshot.viewerUserId,
  )

  if (!viewerParticipant) {
    return null
  }

  const path = getViewerCupPath(
    viewerParticipant.id,
    snapshot.rounds,
    snapshot.ties,
  )

  if (path.length === 0) {
    return null
  }

  const lookup = participantsById(snapshot.participants)

  return (
    <section className="cup-path-section" aria-labelledby="cup-path-heading">
      <h2 id="cup-path-heading">Η πορεία σου</h2>
      <ol className="cup-path-list">
        {path.map((row) => (
          <li key={row.tie.id} className="cup-path-row">
            <PathRow
              row={row}
              viewerParticipant={viewerParticipant}
              lookup={lookup}
              matchday={snapshot.matchdaysById[row.round.matchday_id]}
            />
          </li>
        ))}
      </ol>
    </section>
  )
}

function PathRow({
  row,
  viewerParticipant,
  lookup,
  matchday,
}: {
  row: CupPathRow
  viewerParticipant: CupParticipant
  lookup: Map<number, CupParticipant>
  matchday: PlayersCupSnapshot['matchdaysById'][number] | undefined
}) {
  const subtitle = cupRoundMatchdaySubtitle(row.round.round_number, matchday)
  const presentation = pathPresentation(
    row.tie,
    viewerParticipant,
    lookup,
    row.round.round_number === 6,
  )

  return (
    <>
      <p className="cup-path-round">
        <span>{cupRoundName(row.round.round_number)}</span>
        {subtitle ? <small>{subtitle}</small> : null}
      </p>
      <p className="cup-path-detail" title={presentation.detailTitle}>
        {presentation.detail}
      </p>
      <p className="cup-path-result">
        {presentation.score ? <strong>{presentation.score}</strong> : null}
        <span>{presentation.result}</span>
      </p>
    </>
  )
}

function pathPresentation(
  tie: CupTie,
  viewer: CupParticipant,
  lookup: Map<number, CupParticipant>,
  isFinalRound: boolean,
) {
  const opponentId =
    tie.home_participant_id === viewer.id
      ? tie.away_participant_id
      : tie.home_participant_id
  const opponentName = participantDisplayName(
    opponentId === null ? undefined : lookup.get(opponentId),
  )
  const viewerIsHome = tie.home_participant_id === viewer.id
  const viewerPoints = viewerIsHome ? tie.home_points : tie.away_points
  const opponentPoints = viewerIsHome ? tie.away_points : tie.home_points

  if (tie.outcome === 'bye') {
    return {
      detail: 'BYE',
      detailTitle: 'BYE',
      score: null as string | null,
      result: 'Πέρασε χωρίς αγώνα',
    }
  }

  const homeKnown = tie.home_participant_id !== null
  const awayKnown = tie.away_participant_id !== null

  if (tie.outcome === 'pending' && homeKnown !== awayKnown) {
    return {
      detail: 'Περιμένει αντίπαλο',
      detailTitle: 'Περιμένει αντίπαλο',
      score: null,
      result: 'Αναμονή',
    }
  }

  if (tie.outcome === 'pending') {
    return {
      detail: `vs ${opponentName}`,
      detailTitle: `vs ${opponentName}`,
      score: `${viewerPoints}–${opponentPoints}`,
      result: 'Σε εξέλιξη',
    }
  }

  const viewerWon = tie.winner_participant_id === viewer.id
  const result = isFinalRound
    ? viewerWon
      ? 'Πρωταθλητής'
      : 'Φιναλίστ'
    : viewerWon
      ? 'Πρόκριση'
      : 'Αποκλεισμός'
  const tieBreak = decidedByRuleLabel(tie.decided_by_rule)

  return {
    detail: `vs ${opponentName}`,
    detailTitle: `vs ${opponentName}`,
    score: `${viewerPoints}–${opponentPoints}`,
    result: tieBreak ? `${result} · ${tieBreak}` : result,
  }
}
