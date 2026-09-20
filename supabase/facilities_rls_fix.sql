-- Run once in the SQL Editor.
-- facilities/checkins had insert+select (and delete, for checkins) RLS
-- policies but no UPDATE policy, so `upsert()` failed with a row-level
-- security error whenever it hit the update path of an insert-on-conflict
-- (e.g. registering a meetup at a facility that already exists from an
-- earlier check-in or meetup).

create policy "Signed-in users can update facilities"
on public.facilities for update
using (auth.uid() is not null)
with check (auth.uid() is not null);

create policy "Users can update own checkins"
on public.checkins for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
