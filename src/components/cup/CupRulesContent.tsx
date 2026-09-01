import { locale } from '../../i18n'
import { DEFAULT_CUP_REWARDS, type CupRewards } from '../../lib/cup'
import { CupRulesContentEl } from './CupRulesContentEl'
import { CupRulesContentEn } from './CupRulesContentEn'

type CupRulesContentProps = {
  rewards?: CupRewards
}

export function CupRulesContent({
  rewards = DEFAULT_CUP_REWARDS,
}: CupRulesContentProps) {
  return locale === 'en' ? (
    <CupRulesContentEn rewards={rewards} />
  ) : (
    <CupRulesContentEl rewards={rewards} />
  )
}
