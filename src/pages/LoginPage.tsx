import { useState } from 'react'
import type { FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import {
  getPasswordRecoveryRedirectTo,
  mapAuthError,
} from '../lib/passwordRecovery'
import { t } from '../i18n'

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
      setMessage(t('auth.signInFailed', { detail: error.message }))
      setLoading(false)
      return
    }

    setMessageType('success')
    setMessage(t('auth.signInSuccess'))
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
    setMessage(t('auth.recoverSent'))
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
        <h2 className="auth-heading">{t('auth.recoverTitle')}</h2>

        {!recoverySent && (
          <p className="auth-description">{t('auth.recoverBody')}</p>
        )}

        {recoverySent ? (
          <>
            <p className="auth-message success" role="status" aria-live="polite">
              {message}
            </p>

            <p className="auth-hint">{t('auth.recoverSpamHint')}</p>

            <button
              className="auth-secondary"
              type="button"
              onClick={returnToLogin}
            >
              {t('auth.backToSignIn')}
            </button>
          </>
        ) : (
          <form className="auth-form" onSubmit={handleRecoverySubmit}>
            <div className="form-field">
              <label htmlFor="recover-email">{t('common.email')}</label>

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
                {loading ? t('auth.sending') : t('auth.sendLink')}
              </button>

              <button
                className="auth-secondary"
                type="button"
                onClick={returnToLogin}
              >
                {t('auth.backToSignIn')}
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
      <h2 className="auth-heading">{t('auth.welcomeBack')}</h2>

      <p className="auth-description">{t('auth.welcomeBackBody')}</p>

      <form className="auth-form" onSubmit={handleSubmit}>
        <div className="form-field">
          <label htmlFor="login-email">{t('common.email')}</label>

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
          <label htmlFor="login-password">{t('common.password')}</label>

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
          {t('auth.forgotPassword')}
        </button>

        <button
          className="auth-submit"
          type="submit"
          disabled={loading}
        >
          {loading ? t('auth.signingIn') : t('auth.signIn')}
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
