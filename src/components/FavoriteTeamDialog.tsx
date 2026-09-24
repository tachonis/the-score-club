import { useEffect, useId, useRef, useState } from 'react'
import { t } from '../i18n'
import {
  favoriteIdFromSelection,
  NONE_TEAM_VALUE,
  selectionFromFavorite,
  type TeamChoice,
} from '../lib/favoriteTeam'
import { PlayerShield } from './PlayerShield'

type FavoriteTeamDialogProps = {
  teams: TeamChoice[]
  favoriteTeamId: number | null
  saving: boolean
  errorMessage: string
  onClose: () => void
  onSave: (favoriteTeamId: number | null) => void
}

export function FavoriteTeamDialog({
  teams,
  favoriteTeamId,
  saving,
  errorMessage,
  onClose,
  onSave,
}: FavoriteTeamDialogProps) {
  const titleId = useId()
  const labelId = useId()
  const selectedRef = useRef<HTMLButtonElement | null>(null)
  const [selection, setSelection] = useState(() =>
    selectionFromFavorite(favoriteTeamId),
  )
  const options = [
    {
      value: NONE_TEAM_VALUE,
      name: t('profile.noTeam'),
      teamName: null as string | null,
    },
    ...teams.map((team) => ({
      value: String(team.id),
      name: team.name,
      teamName: team.name,
    })),
  ]

  useEffect(() => {
    selectedRef.current?.focus()
  }, [selection])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !saving) {
        onClose()
      }
    }

    document.addEventListener('keydown', handleKeyDown)
    document.body.classList.add('modal-open')

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.body.classList.remove('modal-open')
    }
  }, [onClose, saving])

  const moveSelection = (direction: 1 | -1 | 'start' | 'end') => {
    const currentIndex = options.findIndex((option) => option.value === selection)
    const nextIndex =
      direction === 'start'
        ? 0
        : direction === 'end'
          ? options.length - 1
          : Math.min(
              options.length - 1,
              Math.max(0, currentIndex + direction),
            )
    const next = options[nextIndex]

    if (!next) return

    setSelection(next.value)
  }

  return (
    <div
      className="rules-overlay"
      onClick={saving ? undefined : onClose}
      role="presentation"
    >
      <section
        className="profile-edit-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="profile-edit-header">
          <h2 id={titleId}>{t('profile.editProfile')}</h2>
          <button
            type="button"
            className="rules-close"
            onClick={onClose}
            disabled={saving}
            aria-label={t('common.close')}
          >
            ×
          </button>
        </header>

        <form
          className="profile-edit-form"
          onSubmit={(event) => {
            event.preventDefault()
            onSave(favoriteIdFromSelection(selection))
          }}
        >
          <div
            className="profile-team-picker"
            role="radiogroup"
            aria-labelledby={labelId}
            onKeyDown={(event) => {
              if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
                event.preventDefault()
                moveSelection(1)
              } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
                event.preventDefault()
                moveSelection(-1)
              } else if (event.key === 'Home') {
                event.preventDefault()
                moveSelection('start')
              } else if (event.key === 'End') {
                event.preventDefault()
                moveSelection('end')
              }
            }}
          >
            <p id={labelId} className="profile-team-label">
              {t('profile.favoriteTeam')}
            </p>
            <div className="profile-team-options">
              {options.map((option) => {
                const selected = option.value === selection

                return (
                  <button
                    key={option.value}
                    ref={selected ? selectedRef : undefined}
                    type="button"
                    role="radio"
                    aria-checked={selected}
                    tabIndex={selected ? 0 : -1}
                    className={`profile-team-option${
                      selected ? ' is-selected' : ''
                    }`}
                    onClick={() => setSelection(option.value)}
                  >
                    <PlayerShield teamName={option.teamName} size={22} />
                    <span>{option.name}</span>
                  </button>
                )
              })}
            </div>
          </div>

          {errorMessage ? (
            <p className="auth-message error">{errorMessage}</p>
          ) : null}

          <div className="profile-edit-actions">
            <button
              type="button"
              className="profile-edit-cancel"
              onClick={onClose}
              disabled={saving}
            >
              {t('common.cancel')}
            </button>
            <button type="submit" className="profile-edit-save" disabled={saving}>
              {saving ? t('common.saving') : t('common.save')}
            </button>
          </div>
        </form>
      </section>
    </div>
  )
}
