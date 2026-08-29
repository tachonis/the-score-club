import { useEffect, useState } from 'react'
import { formatGreekAllCaps } from '../lib/greekAllCaps'
import { supabase } from '../lib/supabase'

type PredictionType = 'winner' | 'league_phase_first'

type Team = {
  id: number
  name: string
  short_name: string | null
}

type StoredSelection = {
  prediction_type: PredictionType
  team_id: number
}

type Award = {
  prediction_type: PredictionType
  points: number
}

type Outcome = {
  prediction_type: PredictionType
  team_id: number
}

type LockStatus = {
  is_locked: boolean
  is_configured: boolean
  matchday_name: string | null
  match_count: number
  finished_count: number
}

const predictionOptions: Array<{
  type: PredictionType
  title: string
  description: string
  points: number
}> = [
  {
    type: 'winner',
    title: 'Νικητής Champions League',
    description: 'Ποια ομάδα θα κατακτήσει το Champions League;',
    points: 30,
  },
  {
    type: 'league_phase_first',
    title: '1η θέση στη League Phase',
    description: 'Ποια ομάδα θα τερματίσει πρώτη στη League Phase;',
    points: 15,
  },
]

const emptySelections: Record<PredictionType, number | null> = {
  winner: null,
  league_phase_first: null,
}

export function LongTermPredictionsSection() {
  const [teams, setTeams] = useState<Team[]>([])
  const [drafts, setDrafts] = useState(emptySelections)
  const [saved, setSaved] = useState(emptySelections)
  const [awards, setAwards] = useState<Partial<Record<PredictionType, number>>>(
    {},
  )
  const [outcomes, setOutcomes] = useState<
    Partial<Record<PredictionType, number>>
  >({})
  const [status, setStatus] = useState<LockStatus | null>(null)
  const [loading, setLoading] = useState(true)
  const [savingType, setSavingType] = useState<PredictionType | null>(null)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )
  const [isManuallyExpanded, setIsManuallyExpanded] = useState(false)

  const loadLongTermPredictions = async () => {
    setLoading(true)

    const [
      teamsResult,
      selectionsResult,
      awardsResult,
      outcomesResult,
      statusResult,
    ] = await Promise.all([
      supabase
        .from('teams')
        .select('id, name, short_name')
        .order('name', { ascending: true }),
      supabase
        .from('long_term_predictions')
        .select('prediction_type, team_id'),
      supabase
        .from('long_term_awards')
        .select('prediction_type, points'),
      supabase
        .from('long_term_outcomes')
        .select('prediction_type, team_id'),
      supabase.rpc('get_long_term_prediction_status'),
    ])

    const firstError = [
      teamsResult.error,
      selectionsResult.error,
      awardsResult.error,
      outcomesResult.error,
      statusResult.error,
    ].find(Boolean)

    if (firstError) {
      setMessageType('error')
      setMessage(`Δεν φορτώθηκαν οι μακροχρόνιες προβλέψεις: ${firstError.message}`)
      setLoading(false)
      return
    }

    const nextSelections = { ...emptySelections }
    const nextAwards: Partial<Record<PredictionType, number>> = {}
    const nextOutcomes: Partial<Record<PredictionType, number>> = {}

    ;((selectionsResult.data ?? []) as StoredSelection[]).forEach(
      (selection) => {
        nextSelections[selection.prediction_type] = selection.team_id
      },
    )
    ;((awardsResult.data ?? []) as Award[]).forEach((award) => {
      nextAwards[award.prediction_type] = award.points
    })
    ;((outcomesResult.data ?? []) as Outcome[]).forEach((outcome) => {
      nextOutcomes[outcome.prediction_type] = outcome.team_id
    })

    setTeams((teamsResult.data ?? []) as Team[])
    setDrafts(nextSelections)
    setSaved(nextSelections)
    setAwards(nextAwards)
    setOutcomes(nextOutcomes)
    setStatus(((statusResult.data ?? [])[0] ?? null) as LockStatus | null)
    setLoading(false)
  }

  useEffect(() => {
    void loadLongTermPredictions()
  }, [])

  const savedCount =
    (saved.winner !== null ? 1 : 0) +
    (saved.league_phase_first !== null ? 1 : 0)
  const isComplete =
    saved.winner !== null && saved.league_phase_first !== null
  const hasPendingEdits =
    drafts.winner !== saved.winner ||
    drafts.league_phase_first !== saved.league_phase_first
  const isLocked = status?.is_locked ?? false

  const isExpanded =
    !isLocked && (!isComplete || hasPendingEdits || isManuallyExpanded)

  const canCollapse =
    isComplete && !hasPendingEdits && !isLocked && isManuallyExpanded

  const handleSave = async (predictionType: PredictionType) => {
    const teamId = drafts[predictionType]

    if (teamId === null) {
      setMessageType('error')
      setMessage('Επίλεξε πρώτα μία ομάδα.')
      return
    }

    setSavingType(predictionType)
    setMessage('')

    const { error } = await supabase.rpc('set_long_term_prediction', {
      p_prediction_type: predictionType,
      p_team_id: teamId,
    })

    if (error) {
      setMessageType('error')
      setMessage(
        error.message === 'Long-term predictions are locked after Matchday 3'
          ? 'Οι μακροχρόνιες προβλέψεις έχουν κλειδώσει μετά την 3η αγωνιστική.'
          : `Δεν αποθηκεύτηκε η επιλογή: ${error.message}`,
      )
      setSavingType(null)
      await loadLongTermPredictions()
      return
    }

    const nextSaved = { ...saved, [predictionType]: teamId }
    setSaved(nextSaved)
    setMessageType('success')
    setMessage(
      saved[predictionType] === null
        ? 'Η μακροχρόνια πρόβλεψη αποθηκεύτηκε.'
        : 'Η αλλαγή της μακροχρόνιας πρόβλεψης αποθηκεύτηκε.',
    )
    setSavingType(null)

    const bothSaved =
      nextSaved.winner !== null && nextSaved.league_phase_first !== null
    const noPendingEdits =
      drafts.winner === nextSaved.winner &&
      drafts.league_phase_first === nextSaved.league_phase_first

    if (bothSaved && noPendingEdits) {
      setIsManuallyExpanded(false)
    }
  }

  const handleCollapse = () => {
    if (canCollapse) {
      setIsManuallyExpanded(false)
      setMessage('')
    }
  }

  const teamName = (teamId: number | null | undefined) => {
    if (teamId === null || teamId === undefined) {
      return '—'
    }

    return teams.find((team) => team.id === teamId)?.name ?? '—'
  }

  const savedTeamLabel = (teamId: number | null) => {
    if (teamId !== null) {
      return teamName(teamId)
    }

    return isLocked ? 'Δεν έχει αποθηκευτεί' : '—'
  }

  const progressLabel = `${savedCount} από 2 ολοκληρωμένες`

  return (
    <section
      className={[
        'long-term-section',
        isLocked ? 'locked' : '',
        !isExpanded ? 'compact' : '',
      ]
        .filter(Boolean)
        .join(' ')}
    >
      {!isExpanded ? (
        <div className="long-term-compact">
          <div className="long-term-compact-main">
            <div className="long-term-compact-heading">
              <p className="dashboard-eyebrow">
                {formatGreekAllCaps('Μακροχρόνιες προβλέψεις')}
              </p>
              <span
                className={`long-term-lock-badge ${
                  isLocked ? 'locked' : 'saved'
                }`}
              >
                <span aria-hidden="true">●</span>
                {isLocked
                  ? formatGreekAllCaps('Κλειδωμένες')
                  : formatGreekAllCaps('Αποθηκευμένες')}
              </span>
            </div>

            <dl className="long-term-compact-summary">
              <div className="long-term-compact-row">
                <dt>Νικητής:</dt>
                <dd>{savedTeamLabel(saved.winner)}</dd>
              </div>
              <div className="long-term-compact-row">
                <dt>1η League Phase:</dt>
                <dd>{savedTeamLabel(saved.league_phase_first)}</dd>
              </div>
            </dl>

            {isLocked && status?.is_configured && (
              <p className="long-term-compact-note">
                {status.finished_count}/{status.match_count} αγώνες της 3ης
                αγωνιστικής ολοκληρώθηκαν.
              </p>
            )}
          </div>

          {!isLocked && (
            <button
              type="button"
              className="long-term-expand-button"
              aria-expanded={isExpanded}
              aria-controls="long-term-editor"
              onClick={() => setIsManuallyExpanded(true)}
            >
              Επεξεργασία
              <span className="long-term-chevron" aria-hidden="true">
                ▼
              </span>
            </button>
          )}
        </div>
      ) : (
        <>
          <div className="long-term-header">
            <div className="long-term-header-primary">
              <p className="dashboard-eyebrow long-term-header-eyebrow">
                {formatGreekAllCaps('Μακροχρόνιες προβλέψεις')}
              </p>

              <div className="long-term-header-title-row">
                <h2>Μακροχρόνιες προβλέψεις</h2>

                {canCollapse && (
                  <button
                    type="button"
                    className="long-term-collapse-button"
                    aria-expanded={isExpanded}
                    aria-controls="long-term-editor"
                    onClick={handleCollapse}
                  >
                    Κλείσιμο
                    <span className="long-term-chevron" aria-hidden="true">
                      ▲
                    </span>
                  </button>
                )}
              </div>

              <div className="long-term-header-meta">
                {!isComplete && (
                  <span className="long-term-completion">{progressLabel}</span>
                )}
                <p className="long-term-deadline-note">
                  {isLocked
                    ? 'Οι μακροχρόνιες προβλέψεις έχουν κλειδώσει.'
                    : 'Αλλαγές έως την ολοκλήρωση της 3ης αγωνιστικής.'}
                </p>
                {!isComplete && !isLocked && (
                  <span className="long-term-points-hint">Έως 45 βαθμοί</span>
                )}
                {status?.is_configured && (
                  <span className="long-term-match-progress">
                    {status.finished_count}/{status.match_count} αγώνες
                    ολοκληρώθηκαν
                  </span>
                )}
              </div>

              <p className="long-term-header-detail">
                {!isComplete ? (
                  <>
                    Έως 45 βαθμοί. Οι αλλαγές επιτρέπονται μέχρι να
                    ολοκληρωθούν όλοι οι αγώνες της 3ης αγωνιστικής της League
                    Phase.
                  </>
                ) : (
                  <>
                    Οι αλλαγές επιτρέπονται μέχρι να ολοκληρωθούν όλοι οι
                    αγώνες της 3ης αγωνιστικής της League Phase.
                  </>
                )}
              </p>
            </div>

            {isLocked && (
              <div className="long-term-header-actions">
                <div className="long-term-lock-badge locked">
                  <span aria-hidden="true">●</span>
                  {formatGreekAllCaps('Κλειδωμένες')}
                </div>
              </div>
            )}
          </div>

          {status?.is_configured && (
            <p className="long-term-deadline">
              {status.is_locked
                ? `Οι μακροχρόνιες προβλέψεις κλειδώθηκαν. ${status.finished_count}/${status.match_count} αγώνες της 3ης αγωνιστικής ολοκληρώθηκαν.`
                : `${status.finished_count}/${status.match_count} αγώνες της 3ης αγωνιστικής ολοκληρώθηκαν.`}
            </p>
          )}

          {message && (
            <p
              className={`auth-message ${messageType === 'error' ? 'error' : 'success'}`}
            >
              {message}
            </p>
          )}

          <div className="long-term-grid" id="long-term-editor">
            {predictionOptions.map((option) => {
              const hasChanged = drafts[option.type] !== saved[option.type]
              const isSaving = savingType === option.type
              const savedTeamId = saved[option.type]

              return (
                <article className="long-term-choice" key={option.type}>
                  <div className="long-term-choice-heading">
                    <div>
                      <h3>{option.title}</h3>
                      <p>{option.description}</p>
                    </div>
                    <strong>+{option.points}</strong>
                  </div>

                  <label>
                    <span className="long-term-choice-label">
                      {formatGreekAllCaps('Η επιλογή σου')}
                    </span>
                    <select
                      value={drafts[option.type] ?? ''}
                      disabled={loading || isLocked || savingType !== null}
                      onChange={(event) => {
                        setMessage('')
                        setDrafts((current) => ({
                          ...current,
                          [option.type]: event.target.value
                            ? Number(event.target.value)
                            : null,
                        }))
                      }}
                    >
                      <option value="">Επίλεξε ομάδα</option>
                      {teams.map((team) => (
                        <option key={team.id} value={team.id}>
                          {team.name}
                        </option>
                      ))}
                    </select>
                  </label>

                  <div className="long-term-choice-footer">
                    <span
                      className={`long-term-state ${
                        isLocked ? 'locked' : hasChanged ? 'changed' : 'saved'
                      }`}
                    >
                      {isLocked
                        ? `Κλειδωμένη: ${teamName(savedTeamId)}`
                        : hasChanged
                          ? 'Αλλαγή σε εκκρεμότητα'
                          : savedTeamId === null
                            ? 'Δεν έχει αποθηκευτεί'
                            : 'Αποθηκευμένη'}
                    </span>

                    {!isLocked && hasChanged && (
                      <button
                        type="button"
                        className="long-term-save-button"
                        disabled={
                          loading ||
                          savingType !== null ||
                          drafts[option.type] === null
                        }
                        onClick={() => void handleSave(option.type)}
                      >
                        {isSaving ? 'Αποθήκευση...' : 'Αποθήκευση'}
                      </button>
                    )}
                  </div>

                  {outcomes[option.type] !== undefined && (
                    <p className="long-term-result">
                      Τελικό outcome:{' '}
                      <strong>{teamName(outcomes[option.type])}</strong>
                      {' · '}
                      Βαθμοί: <strong>{awards[option.type] ?? 0}</strong>
                    </p>
                  )}
                </article>
              )
            })}
          </div>
        </>
      )}
    </section>
  )
}
