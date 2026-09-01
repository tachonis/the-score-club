import { el, type Messages } from './el'
import { en } from './en'

export type { Messages }
export type AppLocale = 'el' | 'en'
export type DateLocale = 'el-GR' | 'en-GB'

type MessageKeyOf<T, Prefix extends string = ''> = {
  [K in keyof T & string]: T[K] extends string
    ? `${Prefix}${K}`
    : MessageKeyOf<T[K], `${Prefix}${K}.`>
}[keyof T & string]

export type MessageKey = MessageKeyOf<typeof el>

export type MessageVars = Record<string, string | number>

export const locale: AppLocale =
  import.meta.env.VITE_APP_LOCALE === 'en' ? 'en' : 'el'

export const dateLocale: DateLocale = locale === 'en' ? 'en-GB' : 'el-GR'

const messages: Messages = locale === 'en' ? en : el

const interpolate = (template: string, vars?: MessageVars) => {
  if (!vars) {
    return template
  }

  return template.replace(
    /\{([a-zA-Z_][a-zA-Z0-9_]*)\}/g,
    (token, name: string) => {
      const value = vars[name]
      return value === undefined ? token : String(value)
    },
  )
}

const readMessage = (tree: Messages, key: MessageKey) => {
  let current: unknown = tree

  for (const part of key.split('.')) {
    if (typeof current !== 'object' || current === null) {
      return key
    }

    current = (current as Record<string, unknown>)[part]
  }

  return typeof current === 'string' ? current : key
}

export const t = (key: MessageKey, vars?: MessageVars) =>
  interpolate(readMessage(messages, key), vars)

// English uses 1 vs other. Greek has more forms; add keys when a string needs them.
export const selectPlural = (
  count: number,
  one: MessageKey,
  other: MessageKey,
) => (count === 1 ? one : other)
