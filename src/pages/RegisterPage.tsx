import { useState } from 'react'
import type { FormEvent } from 'react'
import { supabase } from '../lib/supabase'

export function RegisterPage() {
  const [username, setUsername] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<
    'success' | 'error'
  >('success')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()
    setLoading(true)
    setMessage('')

    const cleanUsername = username.trim()

    if (cleanUsername.length < 3) {
      setMessageType('error')
      setMessage(
        'Το username πρέπει να έχει τουλάχιστον 3 χαρακτήρες.',
      )
      setLoading(false)
      return
    }

    if (password.length < 6) {
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

    const { error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        data: {
          username: cleanUsername,
        },
      },
    })

    if (error) {
      setMessageType('error')
      setMessage(`Δεν ολοκληρώθηκε η εγγραφή: ${error.message}`)
      setLoading(false)
      return
    }

    setMessageType('success')
    setMessage(
      'Η εγγραφή ολοκληρώθηκε. Έλεγξε το email σου για επιβεβαίωση.',
    )

    setUsername('')
    setEmail('')
    setPassword('')
    setConfirmPassword('')
    setLoading(false)
  }

  return (
    <>
      <h2 className="auth-heading">Δημιουργία λογαριασμού</h2>

      <p className="auth-description">
        Δημιούργησε το προφίλ σου για να συμμετέχεις στο παιχνίδι.
      </p>

      <form className="auth-form" onSubmit={handleSubmit}>
        <div className="form-field">
          <label htmlFor="register-username">Username</label>

          <input
            id="register-username"
            type="text"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            autoComplete="username"
            minLength={3}
            required
          />
        </div>

        <div className="form-field">
          <label htmlFor="register-email">Email</label>

          <input
            id="register-email"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            autoComplete="email"
            required
          />
        </div>

        <div className="form-field">
          <label htmlFor="register-password">Κωδικός</label>

          <input
            id="register-password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="new-password"
            minLength={6}
            required
          />
        </div>

        <div className="form-field">
          <label htmlFor="confirm-password">
            Επιβεβαίωση κωδικού
          </label>

          <input
            id="confirm-password"
            type="password"
            value={confirmPassword}
            onChange={(event) =>
              setConfirmPassword(event.target.value)
            }
            autoComplete="new-password"
            minLength={6}
            required
          />
        </div>

        <button
          className="auth-submit"
          type="submit"
          disabled={loading}
        >
          {loading ? 'Γίνεται εγγραφή...' : 'Εγγραφή'}
        </button>
      </form>

      {message && (
        <p
          className={`auth-message ${
            messageType === 'error' ? 'error' : 'success'
          }`}
        >
          {message}
        </p>
      )}
    </>
  )
}
