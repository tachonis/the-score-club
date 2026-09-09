import { t } from '../i18n'
import type { MatchPlayerPrediction } from '../lib/matchPlayerPredictions'

type PlayerPredictionsPanelProps = {
  kickedOff: boolean
  showTeaser: boolean
  rows: MatchPlayerPrediction[]
  viewerUserId: string | null
  revealUnavailable?: boolean
}

export function PlayerPredictionsPanel({
  kickedOff,
  showTeaser,
  rows,
  viewerUserId,
  revealUnavailable = false,
}: PlayerPredictionsPanelProps) {
  if (!kickedOff) {
    if (!showTeaser) {
      return null
    }

    return (
      <p className="player-predictions-teaser">
        {t('predictions.playerPredictionsHidden')}
      </p>
    )
  }

  if (revealUnavailable) {
    return null
  }

  return (
    <details className="player-predictions-panel">
      <summary>
        {t('predictions.playerPredictions')}
        <span className="player-predictions-count">{rows.length}</span>
      </summary>

      {rows.length === 0 ? (
        <p className="player-predictions-empty">
          {t('predictions.playerPredictionsEmpty')}
        </p>
      ) : (
        <ul className="player-predictions-list">
          {rows.map((row) => {
            const isSelf = row.user_id === viewerUserId

            return (
              <li
                key={row.user_id}
                className={`player-prediction-row${isSelf ? ' is-self' : ''}`}
              >
                <span className="player-prediction-username">
                  {row.username}
                  {isSelf ? (
                    <span className="player-prediction-you">
                      {t('common.you')}
                    </span>
                  ) : null}
                </span>

                <span className="player-prediction-meta">
                  <span className="player-prediction-score">
                    {row.predicted_home_score}–{row.predicted_away_score}
                  </span>
                  {row.is_golden_match ? (
                    <span
                      className="player-prediction-golden"
                      title={t('predictions.playerGoldenMatch')}
                      aria-label={t('predictions.playerGoldenMatch')}
                    >
                      ★
                    </span>
                  ) : null}
                  {row.points !== null ? (
                    <span className="player-prediction-points">
                      {t('predictions.playerPoints', { points: row.points })}
                    </span>
                  ) : null}
                </span>
              </li>
            )
          })}
        </ul>
      )}
    </details>
  )
}
