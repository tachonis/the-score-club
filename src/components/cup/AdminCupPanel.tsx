import { useCallback, useEffect, useState } from 'react'
import {
  MINIMUM_CUP_PARTICIPANTS,
  loadPlayersCupSnapshot,
  type PlayersCupSnapshot,
} from '../../lib/cup'
import { supabase } from '../../lib/supabase'

type ConfirmingAction = 'draw' | 'recompute' | null

export function AdminCupPanel() {
  const [snapshot, setSnapshot] = useState<PlayersCupSnapshot | null>(null)
  const [loading, setLoading] = useState(true)
  const [busyAction, setBusyAction] = useState<ConfirmingAction>(null)
  const [confirming, setConfirming] = useState<ConfirmingAction>(null)
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<'success' | 'error'>(
    'success',
  )

  const loadPanel = useCallback(async () => {
    setLoading(true)

    const { snapshot: nextSnapshot, error } = await loadPlayersCupSnapshot()

    if (error) {
      setMessageType('error')
      setMessage(error)
      setSnapshot(null)
    } else {
      setSnapshot(nextSnapshot)
    }

    setLoading(false)
  }, [])

  useEffect(() => {
    void loadPanel()
  }, [loadPanel])

  const reloadSnapshot = async () => {
    const { snapshot: nextSnapshot, error } = await loadPlayersCupSnapshot()

    if (error || !nextSnapshot) {
      setMessageType('error')
      setMessage(
        error ??
          'Η εντολή ολοκληρώθηκε, αλλά δεν φορτώθηκε ξανά η κατάσταση του Κυπέλλου.',
      )
      return null
    }

    setSnapshot(nextSnapshot)
    return nextSnapshot
  }

  const handleDraw = async () => {
    setBusyAction('draw')
    setMessage('')

    const { error } = await supabase.rpc('create_players_cup', {
      p_dry_run: false,
    })

    const nextSnapshot = await reloadSnapshot()

    if (nextSnapshot?.cup) {
      setConfirming(null)
      setBusyAction(null)
      setMessageType('success')
      setMessage(
        error
          ? 'Η κλήρωση έχει ήδη πραγματοποιηθεί.'
          : 'Η κλήρωση ολοκληρώθηκε.',
      )
      return
    }

    setMessageType('error')
    setMessage(
      error
        ? `Δεν πραγματοποιήθηκε η κλήρωση: ${error.message}`
        : 'Η κλήρωση ολοκληρώθηκε, αλλά το Κύπελλο δεν εμφανίζεται ακόμη. Πάτησε ανανέωση.',
    )
    setBusyAction(null)
  }

  const handleRecompute = async () => {
    setBusyAction('recompute')
    setMessage('')

    const { error } = await supabase.rpc('recompute_players_cup')

    if (error) {
      setMessageType('error')
      setMessage(`Δεν επανυπολογίστηκε το Κύπελλο: ${error.message}`)
      setBusyAction(null)
      return
    }

    const nextSnapshot = await reloadSnapshot()

    if (nextSnapshot) {
      setConfirming(null)
      setMessageType('success')
      setMessage('Το Κύπελλο επανυπολογίστηκε από τα αποθηκευμένα αποτελέσματα.')
    }

    setBusyAction(null)
  }

  const formatCreatedAt = (value: string) => {
    return new Intl.DateTimeFormat('el-GR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(new Date(value))
  }

  const cup = snapshot?.cup ?? null
  const rankingReady = Boolean(snapshot?.rankingMatchdaysComplete)
  const enoughPlayers =
    (snapshot?.activePlayerCount ?? 0) >= MINIMUM_CUP_PARTICIPANTS
  const canDraw = !cup && rankingReady && enoughPlayers
  const isBusy = busyAction !== null

  let statusLabel = 'Φόρτωση...'
  let helper = ''

  if (!loading && !snapshot && messageType === 'error') {
    statusLabel = 'Δεν φορτώθηκε'
  } else if (cup) {
    statusLabel = 'Η κλήρωση ολοκληρώθηκε'
  } else if (!snapshot?.rankingMatchdaysExist) {
    statusLabel = 'Δεν έχουν οριστεί αγωνιστικές'
    helper =
      'Η κλήρωση θα είναι διαθέσιμη όταν ολοκληρωθούν η 1η και η 2η αγωνιστική.'
  } else if (!rankingReady) {
    statusLabel = 'Η 2η αγωνιστική δεν έχει ολοκληρωθεί'
    helper =
      'Η κλήρωση θα είναι διαθέσιμη όταν ολοκληρωθούν η 1η και η 2η αγωνιστική.'
  } else if (!enoughPlayers) {
    statusLabel = 'Δεν υπάρχουν αρκετοί παίκτες'
    helper = `Απαιτούνται τουλάχιστον ${MINIMUM_CUP_PARTICIPANTS} ενεργοί παίκτες. Αυτή τη στιγμή υπάρχουν ${snapshot?.activePlayerCount ?? 0}.`
  } else {
    statusLabel = 'Έτοιμο για κλήρωση'
    helper = 'Η κλήρωση είναι οριστική. Το bracket δεν μπορεί να ξαναγίνει.'
  }

  return (
    <section className="admin-cup-panel">
      <div className="admin-cup-panel-heading">
        <div>
          <p className="dashboard-eyebrow">Players Cup</p>
          <h2>Κλήρωση Κυπέλλου</h2>
        </div>
        <span className="matchday-status">{statusLabel}</span>
      </div>

      {message && (
        <p
          className={`auth-message ${
            messageType === 'error' ? 'error' : 'success'
          }`}
        >
          {message}
        </p>
      )}

      {loading ? (
        <p className="admin-cup-helper">Φόρτωση Κυπέλλου...</p>
      ) : !snapshot ? (
        <>
          <p className="admin-cup-helper">
            Δεν φορτώθηκε η κατάσταση του Κυπέλλου.
          </p>
          <button
            type="button"
            className="league-refresh-button"
            onClick={() => void loadPanel()}
          >
            Ανανέωση
          </button>
        </>
      ) : cup ? (
        <>
          <p className="admin-cup-helper">
            {cup.participant_count} παίκτες · {formatCreatedAt(cup.created_at)}
          </p>

          {confirming === 'recompute' ? (
            <div className="admin-notifications-confirm">
              <p>
                Δεν προχωρά γύρο. Ξαναϋπολογίζει την κατάσταση του Κυπέλλου
                από τα αποθηκευμένα αποτελέσματα. Να συνεχίσω;
              </p>
              <div className="admin-notifications-confirm-actions">
                <button
                  type="button"
                  className="admin-save-button"
                  disabled={isBusy}
                  onClick={() => void handleRecompute()}
                >
                  {busyAction === 'recompute'
                    ? 'Επανυπολογισμός...'
                    : 'Επιβεβαίωση'}
                </button>
                <button
                  type="button"
                  className="admin-notifications-cancel"
                  disabled={isBusy}
                  onClick={() => setConfirming(null)}
                >
                  Ακύρωση
                </button>
              </div>
            </div>
          ) : (
            <button
              type="button"
              className="admin-cup-recovery"
              disabled={isBusy}
              onClick={() => {
                setMessage('')
                setConfirming('recompute')
              }}
            >
              Επανυπολογισμός Κυπέλλου
            </button>
          )}
          <p className="admin-cup-recovery-note">
            Δεν προχωρά γύρο. Ξαναϋπολογίζει την κατάσταση του Κυπέλλου από τα
            αποθηκευμένα αποτελέσματα.
          </p>
        </>
      ) : confirming === 'draw' ? (
        <div className="admin-notifications-confirm">
          <p>
            Η κλήρωση είναι οριστική. Το bracket δεν μπορεί να ξαναγίνει. Να
            συνεχίσω;
          </p>
          <div className="admin-notifications-confirm-actions">
            <button
              type="button"
              className="admin-save-button"
              disabled={isBusy}
              onClick={() => void handleDraw()}
            >
              {busyAction === 'draw' ? 'Κλήρωση...' : 'Επιβεβαίωση'}
            </button>
            <button
              type="button"
              className="admin-notifications-cancel"
              disabled={isBusy}
              onClick={() => setConfirming(null)}
            >
              Ακύρωση
            </button>
          </div>
        </div>
      ) : (
        <>
          {helper && <p className="admin-cup-helper">{helper}</p>}
          <button
            type="button"
            className="admin-save-button"
            disabled={!canDraw || isBusy}
            onClick={() => {
              setMessage('')
              setConfirming('draw')
            }}
          >
            Πραγματοποίηση κλήρωσης
          </button>
        </>
      )}
    </section>
  )
}
