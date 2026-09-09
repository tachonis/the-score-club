import { useEffect, useState } from 'react'
import { t, selectPlural } from '../i18n'
import { LoadingMark } from './BrandAssets'
import {
  classifyStoredPredictionPoints,
  fetchPlayerPredictionHistory,
  type PlayerPredictionHistoryGroup,
  type PlayerPredictionHistoryRow,
  type PredictionResultKind,
} from '../lib/playerPredictionHistory'
import { formatMatchdayLabel } from '../lib/stages'
import { getCompactTeamName } from '../lib/teamDisplayName'

type PlayerPredictionHistoryProps = {
  profileUserId: string
}

type HistoryState =
  | { status: 'loading' }
  | { status: 'unavailable' }
  | { status: 'ready'; groups: PlayerPredictionHistoryGroup[] }

const resultLabelKey = (
  kind: PredictionResultKind,
):
  | 'profile.historyExact'
  | 'profile.historyCorrect'
  | 'profile.historyWrong' => {
  if (kind === 'exact') {
    return 'profile.historyExact'
  }

  if (kind === 'correct') {
    return 'profile.historyCorrect'
  }

  return 'profile.historyWrong'
}

const formatScore = (home: number, away: number) => `${home} – ${away}`

const formatPoints = (points: number) => {
  if (points === 0) {
    return t('profile.historyPointsZero')
  }

  return t(
    selectPlural(
      points,
      'profile.historyPoint',
      'profile.historyPoints',
    ),
    { n: points },
  )
}

function HistoryMatchRow({ row }: { row: PlayerPredictionHistoryRow }) {
  const kind = classifyStoredPredictionPoints(row.points)
  const homeFull = row.home_team_name
  const awayFull = row.away_team_name
  const homeShort = getCompactTeamName(
    row.home_team_name,
    row.home_team_short_name,
  )
  const awayShort = getCompactTeamName(
    row.away_team_name,
    row.away_team_short_name,
  )

  return (
    <article
      className={`profile-history-match is-${kind}${
        row.is_golden_match ? ' is-golden' : ''
      }`}
    >
      <div className="profile-history-fixture">
        <span className="profile-history-team is-home">
          <span className="team-name-full">{homeFull}</span>
          <span className="team-name-short">{homeShort}</span>
        </span>
        <span className="profile-history-final" aria-label={t('profile.historyFinalScore')}>
          {formatScore(row.home_score, row.away_score)}
        </span>
        <span className="profile-history-team is-away">
          <span className="team-name-full">{awayFull}</span>
          <span className="team-name-short">{awayShort}</span>
        </span>
      </div>

      <p className="profile-history-prediction">
        {t('profile.historyPrediction')}:{' '}
        {formatScore(row.predicted_home_score, row.predicted_away_score)}
      </p>

      <div className="profile-history-outcome">
        <span className="profile-history-points">{formatPoints(row.points)}</span>
        <span className={`profile-history-result is-${kind}`}>
          {t(resultLabelKey(kind))}
        </span>
      </div>

      {row.is_golden_match ? (
        <p className="profile-history-golden">
          <span aria-hidden="true">★</span> {t('profile.historyGolden')}
        </p>
      ) : null}
    </article>
  )
}

export function PlayerPredictionHistory({
  profileUserId,
}: PlayerPredictionHistoryProps) {
  const [state, setState] = useState<HistoryState>({ status: 'loading' })
  const [openMatchdayIds, setOpenMatchdayIds] = useState<Set<number>>(
    () => new Set(),
  )

  useEffect(() => {
    let cancelled = false

    const loadHistory = async () => {
      setState({ status: 'loading' })
      setOpenMatchdayIds(new Set())

      try {
        const groups = await fetchPlayerPredictionHistory(profileUserId)

        if (cancelled) return

        setState({ status: 'ready', groups })
        setOpenMatchdayIds(
          groups[0] ? new Set([groups[0].matchdayId]) : new Set(),
        )
      } catch {
        if (cancelled) return

        setState({ status: 'unavailable' })
      }
    }

    void loadHistory()

    return () => {
      cancelled = true
    }
  }, [profileUserId])

  const toggleMatchday = (matchdayId: number, isOpen: boolean) => {
    setOpenMatchdayIds((current) => {
      const next = new Set(current)

      if (isOpen) {
        next.add(matchdayId)
      } else {
        next.delete(matchdayId)
      }

      return next
    })
  }

  return (
    <section
      className="profile-history"
      aria-labelledby="profile-history-heading"
      aria-busy={state.status === 'loading'}
    >
      <h2 id="profile-history-heading">{t('profile.historyTitle')}</h2>

      {state.status === 'loading' ? (
        <section className="app-loading-inline">
          <LoadingMark />
          <p>{t('common.loading')}</p>
        </section>
      ) : state.status === 'unavailable' ? (
        <p className="auth-message error">{t('profile.loadHistoryFailed')}</p>
      ) : state.groups.length === 0 ? (
        <p className="profile-history-empty">{t('profile.historyEmpty')}</p>
      ) : (
        <div className="profile-history-groups">
          {state.groups.map((group) => {
            const label = formatMatchdayLabel(
              group.stage,
              group.matchdayNumber,
              group.name,
            )

            return (
              <details
                key={group.matchdayId}
                className="profile-history-matchday"
                open={openMatchdayIds.has(group.matchdayId)}
                onToggle={(event) => {
                  toggleMatchday(
                    group.matchdayId,
                    event.currentTarget.open,
                  )
                }}
              >
                <summary>
                  <span>{label}</span>
                  <span className="profile-history-count">
                    {group.matches.length}
                  </span>
                </summary>

                <div className="profile-history-matches">
                  {group.matches.map((row) => (
                    <HistoryMatchRow key={row.match_id} row={row} />
                  ))}
                </div>
              </details>
            )
          })}
        </div>
      )}
    </section>
  )
}
