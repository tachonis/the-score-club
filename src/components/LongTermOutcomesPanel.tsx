import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

type PredictionType = 'winner' | 'league_phase_first'

type Team = {
  id: number
  name: string
}

type Outcome = {
  prediction_type: PredictionType
  team_id: number
}

type LockStatus = {
  is_locked: boolean
  is_configured: boolean
  match_count: number
  finished_count: number
}

type OutcomeResponse = {
  outcome_changed: boolean
  scored_predictions: number
  changed_awards: number
}

type LongTermOutcomesPanelProps = {
  refreshKey: number
}

const outcomeOptions: Array<{
  type: PredictionType
  title: string
  points: number
}> = [
  { type: 'winner', title: 'Champions League Winner', points: 30 },
  {
    type: 'league_phase_first',
    title: '1st place in League Phase',
    points: 15,
  },
]

const emptyOutcomes: Record<PredictionType, number | null> = {
  winner: null,
  league_phase_first: null,
}

export function LongTermOutcomesPanel({
  refreshKey,
}: LongTermOutcomesPanelProps) {
  const [teams, setTeams] = useState<Team[]>([])
  const [drafts, setDrafts] = useState(emptyOutcomes)
  const [saved, setSaved] = useState(emptyOutcomes)
  const [status, setStatus] = useState<LockStatus | null>(null)
  const [loading, setLoading] = useState(true)
  const [savingType, setSavingType] = useState<PredictionType | null>(null)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )

  const loadOutcomes = async () => {
    setLoading(true)

    const [teamsResult, outcomesResult, statusResult] = await Promise.all([
      supabase.from('teams').select('id, name').order('name'),
      supabase
        .from('long_term_outcomes')
        .select('prediction_type, team_id'),
      supabase.rpc('get_long_term_prediction_status'),
    ])

    const firstError = [
      teamsResult.error,
      outcomesResult.error,
      statusResult.error,
    ].find(Boolean)

    if (firstError) {
      setMessageType('error')
      setMessage(`Δεν φορτώθηκαν τα long-term outcomes: ${firstError.message}`)
      setLoading(false)
      return
    }

    const nextOutcomes = { ...emptyOutcomes }

    ;((outcomesResult.data ?? []) as Outcome[]).forEach((outcome) => {
      nextOutcomes[outcome.prediction_type] = outcome.team_id
    })

    setTeams((teamsResult.data ?? []) as Team[])
    setDrafts(nextOutcomes)
    setSaved(nextOutcomes)
    setStatus(((statusResult.data ?? [])[0] ?? null) as LockStatus | null)
    setLoading(false)
  }

  useEffect(() => {
    void loadOutcomes()
  }, [refreshKey])

  const handleSave = async (predictionType: PredictionType) => {
    const teamId = drafts[predictionType]

    if (teamId === null) return

    setSavingType(predictionType)
    setMessage('')

    const { data, error } = await supabase.rpc('set_long_term_outcome', {
      p_prediction_type: predictionType,
      p_team_id: teamId,
    })

    if (error) {
      setMessageType('error')
      setMessage(
        error.message === 'Long-term outcomes require completed Matchday 3'
          ? 'Τα outcomes μπορούν να καταχωριστούν μόνο μετά την ολοκλήρωση της 3ης αγωνιστικής.'
          : `Δεν αποθηκεύτηκε το outcome: ${error.message}`,
      )
      setSavingType(null)
      return
    }

    const result = (data?.[0] ?? null) as OutcomeResponse | null

    setSaved((current) => ({ ...current, [predictionType]: teamId }))
    setMessageType('success')
    setMessage(
      `Το outcome αποθηκεύτηκε. ${result?.scored_predictions ?? 0} επιλογές ` +
        `ελέγχθηκαν και ${result?.changed_awards ?? 0} βαθμολογίες άλλαξαν.`,
    )
    setSavingType(null)
  }

  const outcomesEnabled = status?.is_configured && status.is_locked

  return (
    <section className="admin-outcomes-panel">
      <div className="admin-outcomes-heading">
        <div>
          <p className="dashboard-eyebrow">Admin-only scoring</p>
          <h2>Long-term outcomes</h2>
          <p>
            Η διόρθωση ενός outcome επανυπολογίζει τους βαθμούς όλων των
            παικτών. Δεν προσθέτει δεύτερη φορά βαθμούς.
          </p>
        </div>
        <span className={outcomesEnabled ? 'ready' : 'waiting'}>
          {outcomesEnabled ? 'Διαθέσιμο' : 'Αναμονή 3ης αγωνιστικής'}
        </span>
      </div>

      {status && !outcomesEnabled && (
        <p className="admin-outcomes-gate">
          {status.finished_count}/{status.match_count} αγώνες της 3ης αγωνιστικής
          έχουν ολοκληρωθεί. Η server-side καταχώριση παραμένει κλειδωμένη.
        </p>
      )}

      {message && (
        <p className={`auth-message ${messageType === 'error' ? 'error' : 'success'}`}>
          {message}
        </p>
      )}

      <div className="admin-outcomes-grid">
        {outcomeOptions.map((option) => {
          const changed = drafts[option.type] !== saved[option.type]
          const isSaving = savingType === option.type

          return (
            <article key={option.type}>
              <div>
                <h3>{option.title}</h3>
                <strong>{option.points} βαθμοί</strong>
              </div>
              <select
                aria-label={`Outcome ${option.title}`}
                value={drafts[option.type] ?? ''}
                disabled={loading || !outcomesEnabled || savingType !== null}
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
                <option value="">Επίλεξε τελικό outcome</option>
                {teams.map((team) => (
                  <option key={team.id} value={team.id}>
                    {team.name}
                  </option>
                ))}
              </select>
              <button
                type="button"
                className="admin-save-button"
                disabled={
                  loading ||
                  !outcomesEnabled ||
                  savingType !== null ||
                  drafts[option.type] === null ||
                  !changed
                }
                onClick={() => void handleSave(option.type)}
              >
                {isSaving
                  ? 'Επανυπολογισμός...'
                  : saved[option.type] === null
                    ? 'Καταχώριση outcome'
                    : 'Διόρθωση & επανυπολογισμός'}
              </button>
            </article>
          )
        })}
      </div>
    </section>
  )
}
