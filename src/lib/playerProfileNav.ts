import { createContext, useContext } from 'react'

export type PlayerProfileNav = {
  viewerUserId: string
  openProfile: (userId: string) => void
}

export const PlayerProfileNavContext = createContext<PlayerProfileNav | null>(
  null,
)

export function usePlayerProfileNav() {
  const value = useContext(PlayerProfileNavContext)

  if (!value) {
    throw new Error(
      'usePlayerProfileNav must be used within PlayerProfileNavContext',
    )
  }

  return value
}
