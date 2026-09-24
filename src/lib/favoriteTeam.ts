import { locale } from '../i18n'
import {
  sortTeamsByName as sortTeamChoices,
  teamsForPicker as teamsForPickerInLocale,
  type TeamChoice,
} from './favoriteTeamSelection'
import { supabase } from './supabase'

export type { TeamChoice }
export {
  NONE_TEAM_VALUE,
  favoriteIdFromSelection,
  selectionFromFavorite,
} from './favoriteTeamSelection'

export const sortTeamsByName = (teams: TeamChoice[]) =>
  sortTeamChoices(teams, locale)

export const teamsForPicker = (
  currentTeams: TeamChoice[],
  savedFavorite: TeamChoice | null,
) => teamsForPickerInLocale(currentTeams, savedFavorite, locale)

const uniqueTeams = (teams: TeamChoice[]) => {
  const byId = new Map<number, TeamChoice>()

  for (const team of teams) {
    if (Number.isInteger(team.id) && team.name.trim()) {
      byId.set(team.id, { id: team.id, name: team.name })
    }
  }

  return sortTeamsByName([...byId.values()])
}

/**
 * Teams that appear in the current League Phase fixture list.
 * A saved favorite outside that list is appended by the caller.
 */
export const loadChampionsLeagueTeams = async (): Promise<TeamChoice[]> => {
  const { data, error } = await supabase
    .from('matches')
    .select(
      `
        home_team_id,
        away_team_id,
        matchdays!inner ( stage )
      `,
    )
    .eq('matchdays.stage', 'league_phase')

  if (error || !data) {
    return []
  }

  const ids = new Set<number>()

  for (const row of data as Array<{
    home_team_id: number
    away_team_id: number
  }>) {
    ids.add(row.home_team_id)
    ids.add(row.away_team_id)
  }

  if (ids.size === 0) {
    return []
  }

  const { data: teams, error: teamsError } = await supabase
    .from('teams')
    .select('id, name')
    .in('id', [...ids])

  if (teamsError || !teams) {
    return []
  }

  return uniqueTeams(teams as TeamChoice[])
}

export const loadTeamById = async (
  teamId: number,
): Promise<TeamChoice | null> => {
  const { data, error } = await supabase
    .from('teams')
    .select('id, name')
    .eq('id', teamId)
    .maybeSingle()

  if (error || !data) {
    return null
  }

  return { id: data.id as number, name: data.name as string }
}

export const loadTeamNameMap = async () => {
  const { data, error } = await supabase.from('teams').select('id, name')

  if (error || !data) {
    return new Map<number, string>()
  }

  return new Map(
    (data as TeamChoice[]).map((team) => [team.id, team.name]),
  )
}
