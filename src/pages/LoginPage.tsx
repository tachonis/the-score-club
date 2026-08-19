import { useState } from 'react'
import type { FormEvent } from 'react'
import { supabase } from '../lib/supabase'

export function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
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
