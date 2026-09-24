export type TeamChoice = {
  id: number
  name: string
}

export const NONE_TEAM_VALUE = 'none'

export const sortTeamsByName = (teams: TeamChoice[], localeName = 'el') =>
  [...teams].sort((left, right) =>
    left.name.localeCompare(right.name, localeName, { sensitivity: 'base' }),
  )

/** Current list, plus a saved favorite that is no longer in that list. */
export const teamsForPicker = (
  currentTeams: TeamChoice[],
  savedFavorite: TeamChoice | null,
  localeName = 'el',
) => {
  const sorted = sortTeamsByName(currentTeams, localeName)

  if (!savedFavorite) {
    return sorted
  }

  if (sorted.some((team) => team.id === savedFavorite.id)) {
    return sorted
  }

  return sortTeamsByName([...sorted, savedFavorite], localeName)
}

export const selectionFromFavorite = (favoriteTeamId: number | null) =>
  favoriteTeamId === null ? NONE_TEAM_VALUE : String(favoriteTeamId)

export const favoriteIdFromSelection = (selection: string): number | null => {
  if (selection === NONE_TEAM_VALUE || selection === '') {
    return null
  }

  const id = Number(selection)

  if (!Number.isInteger(id) || id <= 0) {
    return null
  }

  return id
}
