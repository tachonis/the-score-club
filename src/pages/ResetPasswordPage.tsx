import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import {
  MIN_PASSWORD_LENGTH,
  mapAuthError,
} from '../lib/passwordRecovery'

type ResetPasswordPageProps = {
  onCompleted: () => void
}

export function ResetPasswordPage({
  onCompleted,
}: ResetPasswordPageProps) {
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<
    'success' | 'error'
  >('error')
  const [loading, setLoading] = useState(false)
  const [completed, setCompleted] = useState(false)
  const completedTimer = useRef<number>(0)

  useEffect(() => {
    return () => {
      window.clearTimeout(completedTimer.current)
    }
  }, [])

  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()
    setLoading(true)
    setMessage('')

    if (password.length < MIN_PASSWORD_LENGTH) {
      setMessageType('error')
      setMessage(
        'Ο κωδικός πρέπει να έχει τουλάχιστον 6 χαρακτήρες.',
      )
      setLoading(false)
      return
    }

    if (password !== confirmPassword) {
      setMessageType('error')
      setMessage('Οι δύο κωδικοί δεν ταιριάζουν.')
      setLoading(false)
      return
    }

    const { error } = await supabase.auth.updateUser({
      password,
    })

    if (error) {
      setMessageType('error')
      setMessage(mapAuthError(error))
      setLoading(false)
      return
    }

    setMessageType('success')
    setMessage('Ο κωδικός σου ενημερώθηκε επιτυχώς.')
    setPassword('')
    setConfirmPassword('')
    setCompleted(true)
    setLoading(false)

    completedTimer.current = window.setTimeout(() => {
      onCompleted()
    }, 1600)
  }

  return (
    <>
      <h2 className="auth-heading">Ορισμός νέου κωδικού</h2>

      <p className="auth-description">
        Επίλεξε έναν νέο κωδικό για τον λογαριασμό σου.
      </p>

      <form className="auth-form" onSubmit={handleSubmit}>
        <div className="form-field">
          <label htmlFor="reset-password">Νέος κωδικός</label>

          <input
            id="reset-password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="new-password"
            minLength={MIN_PASSWORD_LENGTH}
            required
          />
        </div>

        <div className="form-field">
          <label htmlFor="reset-confirm-password">
            Επιβεβαίωση νέου κωδικού
          </label>

          <input
            id="reset-confirm-password"
            type="password"
            value={confirmPassword}
            onChange={(event) =>
              setConfirmPassword(event.target.value)
            }
            autoComplete="new-password"
            minLength={MIN_PASSWORD_LENGTH}
            required
          />
        </div>

        <button
          className="auth-submit"
          type="submit"
          disabled={loading || completed}
        >
          {loading
            ? 'Γίνεται αποθήκευση...'
            : 'Αποθήκευση νέου κωδικού'}
        </button>
      </form>

      {message && (
        <p
          className={`auth-message ${
            messageType === 'error' ? 'error' : 'success'
          }`}
          role="status"
          aria-live="polite"
        >
          {message}
        </p>
      )}
    </>
  )
}
