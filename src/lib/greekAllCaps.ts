const COMBINING_MARKS = /[\u0300-\u036f]/g

export function formatGreekAllCaps(value: string) {
  return value.normalize('NFD').replace(COMBINING_MARKS, '').toLocaleUpperCase('en-US')
}
