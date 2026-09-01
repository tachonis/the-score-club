import { DEFAULT_CUP_REWARDS, type CupRewards } from '../../lib/cup'

type CupRulesContentProps = {
  rewards?: CupRewards
}

export function CupRulesContentEn({
  rewards = DEFAULT_CUP_REWARDS,
}: CupRulesContentProps) {
  const winnerPoints = rewards.winner
  const finalistPoints = rewards.finalist
  const semiFinalistPoints = rewards.semiFinalist

  return (
    <>
      <section className="rule-section">
        <h3>Players Cup</h3>
        <p>
          The Players Cup is a separate knockout competition inside The Score
          Club. It starts on League Phase Matchday 3 and finishes with the
          Final on Matchday 8.
        </p>
        <p>
          The predictions you make for the regular matches are used
          automatically in the Cup as well. You do not need to make separate
          predictions.
        </p>
      </section>

      <section className="rule-section">
        <h3>Entry &amp; draw</h3>
        <ul>
          <li>
            Active The Score Club players take part in the Players Cup.
          </li>
          <li>
            At least 8 players are required for the competition to take place.
          </li>
          <li>
            The maximum Cup size is 64 players. If there are more than 64
            active players, the top 64 in the overall standings after Matchday
            2 is complete take part.
          </li>
          <li>
            The draw is made after Matchday 2 is complete, and it is final.
          </li>
          <li>
            The top 8 in the overall standings after Matchday 2 are seeded.
            They are placed in different parts of the bracket so they cannot
            meet before the quarter-finals.
          </li>
          <li>
            If the number of players does not fill a complete bracket, some
            players go through without a tie (BYE). Byes are awarded first by
            ranking after Matchday 2, then by the draw within that group of
            players.
          </li>
        </ul>
      </section>

      <section className="rule-section">
        <h3>Cup rounds</h3>
        <ul>
          <li>Round 1 — Matchday 3</li>
          <li>Round 2 — Matchday 4</li>
          <li>Round 3 — Matchday 5</li>
          <li>Quarter-finals — Matchday 6</li>
          <li>Semi-finals — Matchday 7</li>
          <li>Final — Matchday 8</li>
        </ul>
        <p>
          Each Cup round uses only the points the player scores from
          predictions on that matchday.
        </p>
      </section>

      <section className="rule-section">
        <h3>How the score is calculated</h3>
        <p>
          For every match on that matchday, the usual game scoring applies:
        </p>
        <ul>
          <li>Exact score: 5 points</li>
          <li>Correct result (1–X–2): 2 points</li>
          <li>Miss: 0 points</li>
        </ul>
        <p>
          If a match has been picked as the Golden Match, its points are
          doubled as usual:
        </p>
        <ul>
          <li>Golden Match exact score: 10 points</li>
          <li>Golden Match correct result: 4 points</li>
          <li>Miss: 0 points</li>
        </ul>
        <p>
          There is no extra multiplier just because the player is in the Cup.
        </p>
        <p>
          Points from season predictions do not count towards a Cup tie score.
        </p>
      </section>

      <section className="rule-section">
        <h3>Who goes through</h3>
        <p>
          After the matchday is complete, the player with more Cup points in
          that round goes through.
        </p>
        <p>If they are level on points, these criteria apply in order:</p>
        <ol>
          <li>More exact scores on the matchday.</li>
          <li>More correct results on the matchday.</li>
          <li>
            A better position in the overall standings after Matchday 2 is
            complete.
          </li>
        </ol>
        <p>
          The ranking after Matchday 2 stays frozen for the whole Cup and is
          used only as the last tie-break.
        </p>
      </section>

      <section className="rule-section">
        <h3>Postponed matches</h3>
        <p>For rounds from Matchday 3 through Matchday 7:</p>
        <p>
          If a match has not finished by the time the first match of the next
          League Phase matchday kicks off, that postponed match is dropped
          from that Players Cup round for good.
        </p>
        <p>
          If the match is played later, the prediction points still count in
          the overall The Score Club standings, but not retrospectively in the
          Players Cup.
        </p>
        <p>
          In the Matchday 8 Final there is no next matchday as a cutoff, so
          the Cup waits for the matches that count towards the Final to
          finish.
        </p>
      </section>

      <section className="rule-section">
        <h3>Players Cup prizes</h3>
        <p>
          Players who reach the last stages of the Cup earn extra points in
          the overall standings:
        </p>
        <ul>
          <li>🏆 Champion: +{winnerPoints} points</li>
          <li>🥈 Finalist: +{finalistPoints} points</li>
          <li>
            Semi-final loser: +{semiFinalistPoints} points
          </li>
        </ul>
        <p>
          Each of the two semi-final losers receives that bonus.
        </p>
        <p>The prizes are not cumulative.</p>
        <p>
          For example, the Champion receives +{winnerPoints} points in total,
          not the sum of the bonuses from earlier rounds.
        </p>
      </section>

      <section className="rule-section">
        <h3>Relation to the overall standings</h3>
        <p>
          Points you score from matchday predictions still count as usual in
          the overall standings.
        </p>
        <p>
          The same score is also used to decide your Players Cup tie.
        </p>
        <p>
          Those same points are not added a second time to the overall
          standings because they were used in the Cup.
        </p>
        <p>
          Only the final Players Cup bonus (+{winnerPoints}, +{finalistPoints}{' '}
          or +{semiFinalistPoints}) is added extra to the overall standings.
        </p>
        <p>
          The Players Cup rewards not only consistency across the season, but
          also a player’s ability to beat successive opponents in knockout
          ties.
        </p>
      </section>
    </>
  )
}
