import {
  AppHeader,
  type AppDestination,
} from '../components/AppHeader'
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
          <h1>Κανόνες παιχνιδιού</h1>
          <p>
            Όλα όσα χρειάζεσαι για τις προβλέψεις, τη βαθμολογία και τις
            ισοβαθμίες, στην ίδια έκδοση κανόνων που εμφανίζεται πριν τη
            σύνδεση.
          </p>
        </section>

        <section className="rules-page-card" aria-labelledby="rules-page-title">
          <header className="rules-page-card-header">
            <div>
              <span>{formatGreekAllCaps('Επίσημοι κανόνες')}</span>
              <h2 id="rules-page-title">Πώς παίζεται</h2>
            </div>
            <div className="rules-score-key" aria-label="Βασική βαθμολογία">
              <span><strong>5</strong> ακριβές</span>
              <span><strong>2</strong> αποτέλεσμα</span>
              <span><strong>0</strong> λάθος</span>
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
