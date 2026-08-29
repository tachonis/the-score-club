import type { KeyboardEvent, Ref } from 'react'

type ScoreStepperProps = {
  value: string
  disabled: boolean
  inputLabel: string
  incrementLabel: string
  decrementLabel: string
  inputRef?: Ref<HTMLInputElement>
  onChange: (value: string, source?: 'stepper' | 'input') => void
}

const MAX_SCORE = 20

const chevronProps = {
  viewBox: '0 0 12 8',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.6,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true as const,
  focusable: false as const,
}

export function ScoreStepper({
  value,
  disabled,
  inputLabel,
  incrementLabel,
  decrementLabel,
  inputRef,
  onChange,
}: ScoreStepperProps) {
  const parsed = value === '' ? null : Number(value)
  const canDecrement = !disabled && parsed !== null && parsed > 0
  const canIncrement =
    !disabled && (parsed === null || parsed < MAX_SCORE)

  const applyDelta = (delta: 1 | -1) => {
    if (disabled) return

    if (value === '') {
      if (delta < 0) return
      onChange('1', 'stepper')
      return
    }

    const next = Number(value) + delta

    if (next < 0 || next > MAX_SCORE) return

    onChange(String(next), 'stepper')
  }

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'ArrowUp') {
      event.preventDefault()
      applyDelta(1)
    }

    if (event.key === 'ArrowDown') {
      event.preventDefault()
      applyDelta(-1)
    }
  }

  return (
    <div className="score-stepper">
      <button
        type="button"
        className="score-stepper-button"
        tabIndex={-1}
        disabled={!canIncrement}
        aria-label={incrementLabel}
        onClick={() => applyDelta(1)}
      >
        <svg width="10" height="6" {...chevronProps}>
          <path d="M1 5 5 1.2 9 5" />
        </svg>
      </button>

      <input
        ref={inputRef}
        type="text"
        inputMode="numeric"
        maxLength={2}
        value={value}
        disabled={disabled}
        aria-label={inputLabel}
        onFocus={(event) => event.target.select()}
        onKeyDown={handleKeyDown}
        onChange={(event) => onChange(event.target.value, 'input')}
      />

      <button
        type="button"
        className="score-stepper-button"
        tabIndex={-1}
        disabled={!canDecrement}
        aria-label={decrementLabel}
        onClick={() => applyDelta(-1)}
      >
        <svg width="10" height="6" {...chevronProps}>
          <path d="M1 1.2 5 5 9 1.2" />
        </svg>
      </button>
    </div>
  )
}
