import { useEffect, useRef } from 'react'
import { t } from '../i18n'
import type { PendingAdminResult } from '../lib/adminResult'

type AdminResultConfirmModalProps = {
  pending: PendingAdminResult
  saving: boolean
  errorText: string
  onCancel: () => void
  onConfirm: () => void
}

const ScoreLine = ({
  homeName,
  awayName,
  homeScore,
  awayScore,
}: {
  homeName: string
  awayName: string
  homeScore: number
  awayScore: number
}) => {
  return (
    <div className="admin-result-confirm-fixture">
      <p className="admin-result-confirm-team">{homeName}</p>
      <p className="admin-result-confirm-score">
        <span>{homeScore}</span>
        <span aria-hidden="true">–</span>
        <span>{awayScore}</span>
      </p>
      <p className="admin-result-confirm-team">{awayName}</p>
    </div>
  )
}

export function AdminResultConfirmModal({
  pending,
  saving,
  errorText,
  onCancel,
  onConfirm,
}: AdminResultConfirmModalProps) {
  const isCorrection = pending.kind === 'correction'
  const dialogRef = useRef<HTMLElement>(null)

  useEffect(() => {
    dialogRef.current?.focus()
  }, [])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !saving) {
        onCancel()
      }
    }

    document.addEventListener('keydown', handleKeyDown)
    document.body.classList.add('modal-open')

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.body.classList.remove('modal-open')
    }
  }, [onCancel, saving])

  return (
    <div className="rules-overlay" role="presentation">
      <section
        ref={dialogRef}
        className="admin-result-confirm"
        role="dialog"
        aria-modal="true"
        aria-labelledby="admin-result-confirm-title"
        tabIndex={-1}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="admin-result-confirm-header">
          <p className="rules-eyebrow">
            {isCorrection
              ? t('admin.confirmCorrectionEyebrow')
              : t('admin.confirmEntry')}
          </p>
          <h2 id="admin-result-confirm-title">
            {isCorrection
              ? t('admin.correctionTitle')
              : t('admin.confirmTitle')}
          </h2>
        </header>

        <div className="admin-result-confirm-body">
          {isCorrection ? (
            <div className="admin-result-confirm-compare">
              <p className="admin-result-confirm-team">{pending.homeName}</p>
              <div className="admin-result-confirm-score-pair">
                <div>
                  <p className="admin-result-confirm-label">{t('admin.current')}</p>
                  <p className="admin-result-confirm-score">
                    <span>{pending.storedHomeScore ?? 0}</span>
                    <span aria-hidden="true">–</span>
                    <span>{pending.storedAwayScore ?? 0}</span>
                  </p>
                </div>
                <div>
                  <p className="admin-result-confirm-label">{t('admin.next')}</p>
                  <p className="admin-result-confirm-score">
                    <span>{pending.homeScore}</span>
                    <span aria-hidden="true">–</span>
                    <span>{pending.awayScore}</span>
                  </p>
                </div>
              </div>
              <p className="admin-result-confirm-team">{pending.awayName}</p>
            </div>
          ) : (
            <ScoreLine
              homeName={pending.homeName}
              awayName={pending.awayName}
              homeScore={pending.homeScore}
              awayScore={pending.awayScore}
            />
          )}

          <p className="admin-result-confirm-copy">
            {isCorrection
              ? t('admin.correctionNote')
              : t('admin.entryNote')}
          </p>
          {errorText ? (
            <p className="admin-result-confirm-error">{errorText}</p>
          ) : null}
        </div>

        <footer className="admin-result-confirm-footer">
          <button
            type="button"
            className="admin-notifications-cancel"
            disabled={saving}
            onClick={onCancel}
          >
            {t('common.cancel')}
          </button>
          <button
            type="button"
            className="admin-save-button"
            disabled={saving}
            onClick={onConfirm}
          >
            {saving
              ? t('common.saving')
              : isCorrection
                ? t('admin.submitCorrection')
                : t('admin.submitEntry')}
          </button>
        </footer>
      </section>
    </div>
  )
}
