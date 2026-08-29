import { useState } from 'react'
import type { FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import {
  getPasswordRecoveryRedirectTo,
  mapAuthError,
} from '../lib/passwordRecovery'

export function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [message, setMessage] = useState('')
  const [messageType, setMessageType] = useState<
    'success' | 'error'
  >('success')
  const [loading, setLoading] = useState(false)
  const [view, setView] = useState<'login' | 'recover'>('login')
  const [recoverySent, setRecoverySent] = useState(false)

  const handleSubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()
    setLoading(true)
    setMessage('')

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    })

    if (error) {
      setMessageType('error')
      setMessage(`Δεν ήταν δυνατή η σύνδεση: ${error.message}`)
      setLoading(false)
      return
    }

    setMessageType('success')
    setMessage('Η σύνδεση ολοκληρώθηκε επιτυχώς.')
    setLoading(false)
  }

  const handleRecoverySubmit = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault()
    setLoading(true)
    setMessage('')

    const { error } = await supabase.auth.resetPasswordForEmail(
      email.trim(),
      {
        redirectTo: getPasswordRecoveryRedirectTo(),
      },
    )

    if (error) {
      setMessageType('error')
      setMessage(mapAuthError(error))
      setLoading(false)
      return
    }

    setRecoverySent(true)
    setMessageType('success')
    setMessage(
      'Σου στείλαμε email με οδηγίες για την επαναφορά του κωδικού σου.',
    )
    setLoading(false)
  }

  const returnToLogin = () => {
    setView('login')
    setRecoverySent(false)
    setMessage('')
    setLoading(false)
  }

  if (view === 'recover') {
    return (
      <>
        <h2 className="auth-heading">Επαναφορά κωδικού</h2>

        {!recoverySent && (
          <p className="auth-description">
            Συμπλήρωσε το email σου και θα σου στείλουμε σύνδεσμο
            για να ορίσεις νέο κωδικό.
          </p>
        )}

        {recoverySent ? (
          <>
            <p className="auth-message success" role="status" aria-live="polite">
              {message}
            </p>

            <p className="auth-hint">
              Έλεγξε και τον φάκελο ανεπιθύμητης αλληλογραφίας.
            </p>

            <button
              className="auth-secondary"
              type="button"
              onClick={returnToLogin}
            >
              Επιστροφή στη σύνδεση
            </button>
          </>
        ) : (
          <form className="auth-form" onSubmit={handleRecoverySubmit}>
            <div className="form-field">
              <label htmlFor="recover-email">Email</label>

              <input
                id="recover-email"
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                autoComplete="email"
                required
              />
            </div>

            <div className="auth-actions">
              <button
                className="auth-submit"
                type="submit"
                disabled={loading}
              >
                {loading
                  ? 'Γίνεται αποστολή...'
                  : 'Αποστολή συνδέσμου'}
              </button>

              <button
                className="auth-secondary"
                type="button"
                onClick={returnToLogin}
              >
                Επιστροφή στη σύνδεση
              </button>
            </div>
          </form>
        )}

        {message && !recoverySent && (
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

  return (
    <>
      <h2 className="auth-heading">Καλώς ήρθες ξανά</h2>

      <p className="auth-description">
        Συνδέσου για να συνεχίσεις τις προβλέψεις σου.
      </p>

      <form className="auth-form" onSubmit={handleSubmit}>
        <div className="form-field">
          <label htmlFor="login-email">Email</label>

          <input
            id="login-email"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            autoComplete="email"
            required
          />
        </div>

        <div className="form-field">
          <label htmlFor="login-password">Κωδικός</label>

          <input
            id="login-password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="current-password"
            required
          />
        </div>

        <button
          className="auth-forgot"
          type="button"
          onClick={() => {
            setView('recover')
            setRecoverySent(false)
            setMessage('')
          }}
        >
          Ξέχασες τον κωδικό σου;
        </button>

        <button
          className="auth-submit"
          type="submit"
          disabled={loading}
        >
          {loading ? 'Γίνεται σύνδεση...' : 'Σύνδεση'}
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
