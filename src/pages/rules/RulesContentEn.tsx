import { CupRulesContent } from '../../components/cup/CupRulesContent'

export function RulesContentEn() {
  return (
    <>
      <section className="rule-section">
        <h3>Aim of the game</h3>
        <p>
          Predict Champions League match scores and collect points throughout
          the competition.
        </p>
      </section>

      <section className="rule-section">
        <h3>Match scoring</h3>
        <ul>
          <li><strong>5 points</strong> for an exact score.</li>
          <li>
            <strong>2 points</strong> for a correct result (winner or draw).
          </li>
          <li><strong>0 points</strong> for a miss.</li>
        </ul>
        <p>
          Predictions are for the 90-minute score, including stoppage time.
          Extra time and penalties do not count.
        </p>
      </section>

      <section className="rule-section">
        <h3>Locked predictions</h3>
        <p>
          Each prediction can be changed until the scheduled kickoff of that
          match. After kickoff, the prediction is locked automatically.
        </p>
      </section>

      <section className="rule-section">
        <h3>Golden Match</h3>
        <p>
          Golden Match applies only in the League Phase, from Matchday 2
          onwards. You can pick one match per matchday as the Golden Match.
          Its points are doubled:
        </p>
        <ul>
          <li><strong>10 points</strong> for an exact score.</li>
          <li><strong>4 points</strong> for a correct result.</li>
          <li><strong>0 points</strong> for a miss.</li>
        </ul>
        <p>
          The pick must be made before that match kicks off. Until then you
          can change it, and the new pick replaces the previous one. After
          kickoff of the selected match, it is locked. An unused Golden Match
          does not carry over to the next matchday.
        </p>
        <p>
          There is no Golden Match in the Champions League knockout stage.
        </p>
      </section>

      <section className="rule-section">
        <h3>Knockout stage &amp; Final</h3>
        <p>
          After the League Phase, predictions continue through the Champions
          League knockout stage.
        </p>
        <p>Each real match is a separate prediction.</p>

        <h4>Two-legged ties</h4>
        <p>
          The Knockout Play-offs, Round of 16, Quarter-finals and Semi-finals
          are played over two legs.
        </p>
        <p>
          The first leg and second leg are predicted separately.
        </p>
        <p>Each match:</p>
        <ul>
          <li>has its own prediction</li>
          <li>locks separately at its own kickoff</li>
          <li>is scored separately</li>
        </ul>
        <p>There is no prediction for:</p>
        <ul>
          <li>which team goes through</li>
          <li>the aggregate score</li>
          <li>how a team qualifies</li>
          <li>extra time</li>
          <li>penalties</li>
        </ul>

        <h4>Which score is predicted</h4>
        <p>
          For every match, the prediction is only the score after 90 minutes
          plus stoppage time.
        </p>
        <p>
          Extra time and penalties do not count in The Score Club scoring.
        </p>
        <p>
          Example: if a match is 1–1 after 90 minutes and finishes 2–1 after
          extra time, The Score Club result is 1–1.
        </p>

        <h4>Knockout match scoring</h4>
        <p>
          For the Knockout Play-offs, Round of 16, Quarter-finals and
          Semi-finals, the usual scoring applies:
        </p>
        <ul>
          <li>
            <strong>Exact score:</strong> 5 points
          </li>
          <li>
            <strong>Correct result (1–X–2):</strong> 2 points
          </li>
          <li>
            <strong>Miss:</strong> 0 points
          </li>
        </ul>
        <p>
          There is no extra bonus for going through or for the aggregate score.
        </p>

        <h4>Final</h4>
        <p>The Final is a single match.</p>
        <p>
          In the Final as well, the prediction is only the 90-minute score plus
          stoppage time.
        </p>
        <p>The Final is scored x2:</p>
        <ul>
          <li>
            <strong>Exact score:</strong> 10 points
          </li>
          <li>
            <strong>Correct result (1–X–2):</strong> 4 points
          </li>
          <li>
            <strong>Miss:</strong> 0 points
          </li>
        </ul>
        <p>Extra time and penalties do not count.</p>

        <h4>Golden Match</h4>
        <p>
          Golden Match applies only in the League Phase, from Matchday 2
          onwards.
        </p>
        <p>There is no Golden Match in:</p>
        <ul>
          <li>Knockout Play-offs</li>
          <li>Round of 16</li>
          <li>Quarter-finals</li>
          <li>Semi-finals</li>
          <li>the Final</li>
        </ul>

        <h4>Knockout points in tie-breaks</h4>
        <p>
          Points a player scores from Knockout Play-offs, Round of 16,
          Quarter-finals, Semi-finals and the Final are used as one of the
          tie-break criteria in the overall standings.
        </p>
        <p>
          Points from the League Phase, Players Cup prizes and season
          predictions are not included in this specific criterion.
        </p>
      </section>

      <section className="rule-section">
        <h3>Season predictions</h3>
        <p>
          Each player can pick one team from the teams in the competition for
          each of the two categories:
        </p>
        <ul>
          <li>
            <strong>30 points</strong> for correctly predicting the champion.
          </li>
          <li>
            <strong>15 points</strong> for correctly predicting the League Phase
            winner.
          </li>
        </ul>
        <p>
          Picks can be changed until League Phase Matchday 3 is complete. Once
          every match of that matchday has finished, both picks are locked. A
          correct pick scores the full points; a miss scores 0.
        </p>
      </section>

      <CupRulesContent />

      <section className="rule-section">
        <h3>Tie-breaks</h3>
        <p>If players are level on points, these criteria apply in order:</p>
        <ol>
          <li>more exact scores</li>
          <li>more correct results</li>
          <li>more knockout-stage points</li>
          <li>fewer missed predictions</li>
        </ol>
        <p>
          If players are still level, they share the same position.
        </p>
        <p>
          Knockout-stage points come from predictions in the Knockout
          Play-offs, Round of 16, Quarter-finals, Semi-finals and Final. They
          do not include League Phase, Players Cup or season predictions.
        </p>
        <p>
          Missed predictions are finished matches for which the player had no
          prediction.
        </p>
      </section>
    </>
  )
}
