import { useState } from 'react'
import type { FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { getAuthRedirectTo } from '../lib/passwordRecovery'
import { mapRegisterError, validateUsername } from '../lib/username'
import { t } from '../i18n'

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
    const usernameError = validateUsername(cleanUsername)

    if (usernameError) {
      setMessageType('error')
      setMessage(usernameError)
      setLoading(false)
      return
    }

    if (password.length < 6) {
      setMessageType('error')
      setMessage(t('auth.passwordTooShort'))
      setLoading(false)
      return
    }

    if (password !== confirmPassword) {
      setMessageType('error')
      setMessage(t('auth.passwordsMismatch'))
      setLoading(false)
      return
    }

    const { error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        emailRedirectTo: getAuthRedirectTo(),
        data: {
          username: cleanUsername,
        },
      },
    })

    if (error) {
      setMessageType('error')
      setMessage(mapRegisterError(error))
      setLoading(false)
      return
    }

    setMessageType('success')
    setMessage(t('auth.registerSuccess'))

    setUsername('')
    setEmail('')
    setPassword('')
    setConfirmPassword('')
    setLoading(false)
  }

  return (
    <>
      <h2 className="auth-heading">{t('auth.createAccount')}</h2>

      <p className="auth-description">{t('auth.createAccountBody')}</p>

      <form className="auth-form" onSubmit={handleSubmit}>
        <div className="form-field">
          <label htmlFor="register-username">{t('common.username')}</label>

          <input
            id="register-username"
            type="text"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            autoComplete="username"
            required
          />
        </div>

        <div className="form-field">
          <label htmlFor="register-email">{t('common.email')}</label>

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
          <label htmlFor="register-password">{t('common.password')}</label>

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
            {t('auth.confirmPassword')}
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
          {loading ? t('auth.registering') : t('auth.register')}
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
