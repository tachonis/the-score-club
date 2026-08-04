import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase'

function App() {
  const [status, setStatus] = useState('Έλεγχος σύνδεσης...')

  useEffect(() => {
    const checkConnection = async () => {
      const { error } = await supabase.auth.getSession()

      if (error) {
        setStatus(`Σφάλμα σύνδεσης: ${error.message}`)
        return
      }

      setStatus('Η σύνδεση με το Supabase λειτουργεί σωστά.')
    }

    checkConnection()
  }, [])

  return (
    <main style={{ padding: '2rem', fontFamily: 'Arial, sans-serif' }}>
      <h1>The Score Club</h1>
      <p>{status}</p>
    </main>
  )
}

export default App
