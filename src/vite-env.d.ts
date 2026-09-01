/// <reference types="vite/client" />

interface ImportMetaEnv {
  /**
   * Build-time UI locale. Only the exact value `en` selects English.
   * Missing, empty, `el`, or any other value falls back to Greek.
   */
  readonly VITE_APP_LOCALE?: string
}
