import { locale } from '../i18n'
import { RulesContentEl } from './rules/RulesContentEl'
import { RulesContentEn } from './rules/RulesContentEn'

export function RulesContent() {
  return locale === 'en' ? <RulesContentEn /> : <RulesContentEl />
}
