import { useEffect } from 'react'
import { RulesContent } from './RulesContent'

type RulesModalProps = {
  onClose: () => void
}

export function RulesModal({ onClose }: RulesModalProps) {
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
        aria-labelledby="rules-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="rules-header">
          <div>
            <p className="rules-eyebrow">The Score Club</p>
            <h2 id="rules-title">Πώς παίζεται</h2>
          </div>

          <button
            type="button"
            className="rules-close"
            onClick={onClose}
            aria-label="Κλείσιμο κανόνων"
          >
            ×
          </button>
        </header>

        <div className="rules-content">
          <RulesContent />
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
