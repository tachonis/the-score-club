-- Prediction writes require an active profile.
--
-- Disabled accounts keep an Auth session until the app signs them out, so
-- INSERT/UPDATE on public.predictions must not rely on the frontend alone.
-- SELECT policies are unchanged: a disabled user may still read their own
-- historical predictions.
--
-- Do not db push from this file. Do not repair migration history.
-- Apply to hosted Supabase only after review.

drop policy if exists "Users can create their own predictions"
  on public.predictions;
create policy "Users can create their own predictions"
  on public.predictions
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.status = 'active'
    )
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  );

drop policy if exists "Users can update their own predictions"
  on public.predictions;
create policy "Users can update their own predictions"
  on public.predictions
  for update
  to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.status = 'active'
    )
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.status = 'active'
    )
    and exists (
      select 1
      from public.matches
      where public.matches.id = public.predictions.match_id
        and public.matches.status = 'scheduled'
        and now() < public.matches.kickoff_at
    )
  );
