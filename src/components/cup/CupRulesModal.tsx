import { useEffect } from 'react'
import { DEFAULT_CUP_REWARDS, type CupRewards } from '../../lib/cup'
import { CupRulesContent } from './CupRulesContent'

type CupRulesModalProps = {
  rewards?: CupRewards
  onClose: () => void
}

export function CupRulesModal({
  rewards = DEFAULT_CUP_REWARDS,
  onClose,
}: CupRulesModalProps) {
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        onClose()
      }
    }

    document.addEventListener('keydown', handleKeyDown)
    document.body.classList.add('modal-open')

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.body.classList.remove('modal-open')
    }
  }, [onClose])

  return (
    <div
      className="rules-overlay"
      onClick={onClose}
      role="presentation"
    >
      <section
        className="rules-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="cup-rules-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="rules-header">
          <div>
            <p className="rules-eyebrow">Players Cup</p>
            <h2 id="cup-rules-title">Κανόνες Players Cup</h2>
          </div>

          <button
            type="button"
            className="rules-close"
            onClick={onClose}
            aria-label="Κλείσιμο κανόνων Κυπέλλου"
          >
            ×
          </button>
        </header>

        <div className="rules-content">
          <CupRulesContent rewards={rewards} />
        </div>

        <footer className="rules-footer">
          <button
            type="button"
            className="rules-done"
            onClick={onClose}
          >
            Κλείσιμο
          </button>
        </footer>
      </section>
    </div>
  )
}
