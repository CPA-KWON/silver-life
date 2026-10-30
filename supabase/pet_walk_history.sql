-- No contacts, phone numbers or precise paths are stored here.
begin;
create table if not exists public.pet_walk_summaries(
 walk_id uuid primary key references public.pet_walks on delete cascade,
 user_id uuid not null references auth.users on delete cascade,steps integer not null,
 seconds integer not null check(seconds>=0),eligible boolean not null,created_at timestamptz not null default now()
);
alter table public.pet_walk_summaries enable row level security;
revoke all on public.pet_walk_summaries from public,anon,authenticated;
grant select on public.pet_walk_summaries to authenticated;
drop policy if exists own_read on public.pet_walk_summaries;
create policy own_read on public.pet_walk_summaries for select to authenticated using(user_id=auth.uid());
create or replace function public.pet_record_walk(p_id uuid,p_seconds integer) returns void
language plpgsql security definer set search_path='' as $$
declare w public.pet_walks;
begin
 if auth.uid() is null then raise exception 'login required';end if;
 select * into w from public.pet_walks where id=p_id and user_id=auth.uid() for update;
 if not found then raise exception '본인 산책을 확인해주세요.';end if;
 if p_seconds<0 or p_seconds>extract(epoch from now()-w.started_at)+10 then raise exception '산책 시간을 확인해주세요.';end if;
 insert into public.pet_walk_summaries(walk_id,user_id,steps,seconds,eligible) values(w.id,w.user_id,w.steps,p_seconds,w.eligible)
 on conflict(walk_id) do update set steps=greatest(pet_walk_summaries.steps,excluded.steps),seconds=greatest(pet_walk_summaries.seconds,excluded.seconds),eligible=pet_walk_summaries.eligible or excluded.eligible;
end $$;
revoke all on function public.pet_record_walk(uuid,integer) from public,anon,authenticated;
grant execute on function public.pet_record_walk(uuid,integer) to authenticated;
commit;
