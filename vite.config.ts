import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const appLocale = env.VITE_APP_LOCALE === 'en' ? 'en' : 'el'

  return {
    plugins: [
      react(),
      {
        name: 'app-locale-html',
        transformIndexHtml(html: string) {
          if (appLocale !== 'en') {
            return html
          }

          return html
            .replace('lang="el"', 'lang="en"')
            .replace(
              'href="/manifest.webmanifest"',
              'href="/manifest.en.webmanifest"',
            )
        },
      },
    ],
  }
})
