import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
import { t } from '../i18n'
import { RulesContent } from './RulesContent'
import { formatGreekAllCaps } from '../lib/greekAllCaps'

type RulesPageProps = {
  username: string
  role: 'player' | 'admin'
  onNavigate: (destination: AppDestination) => void
  onLogout: () => Promise<void>
}

export function RulesPage({
  username,
  role,
  onNavigate,
  onLogout,
}: RulesPageProps) {
  return (
    <div className="app-shell">
      <AppHeader
        currentPage="rules"
        username={username}
        role={role}
        onNavigate={onNavigate}
        onLogout={onLogout}
      />

      <main className="rules-page-main">
        <section className="rules-page-intro">
          <p className="dashboard-eyebrow">The Score Club</p>
          <h1>{t('rules.pageTitle')}</h1>
          <p>
            {t('rules.pageIntro')}
          </p>
        </section>

        <section className="rules-page-card" aria-labelledby="rules-page-title">
          <header className="rules-page-card-header">
            <div>
              <span>{formatGreekAllCaps(t('rules.official'))}</span>
              <h2 id="rules-page-title">{t('auth.rulesTitle')}</h2>
            </div>
            <div className="rules-score-key" aria-label={t('rules.scoreKeyAria')}>
              <span><strong>5</strong> {t('rules.exactShort')}</span>
              <span><strong>2</strong> {t('rules.resultShort')}</span>
              <span><strong>0</strong> {t('rules.missShort')}</span>
            </div>
          </header>

          <div className="rules-page-content">
            <RulesContent />
          </div>
        </section>
      </main>
    </div>
  )
}
