-- J02–J06. Apply after neighborhood_mockups.sql. Canonical membership stays
-- meetup_participants; this private table records only a member's own withdrawal.
begin;
create table if not exists public.meetup_withdrawals (
 post_id uuid not null references public.posts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 withdrawn_at timestamptz not null default now(),
 primary key(post_id,user_id)
);
alter table public.meetup_withdrawals enable row level security;
revoke all on public.meetup_withdrawals from public,anon,authenticated;
create or replace function public.meetup_record_withdrawal() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
  -- Parent deletion/account deletion is cleanup, not a participant withdrawal.
  if auth.uid()=old.user_id and exists(select 1 from public.posts where id=old.post_id and author_id<>old.user_id)
     and exists(select 1 from auth.users where id=old.user_id) then
   insert into public.meetup_withdrawals(post_id,user_id) values(old.post_id,old.user_id)
    on conflict(post_id,user_id) do update set withdrawn_at=now();
  end if;
  return old;
 end if;
 delete from public.meetup_withdrawals where post_id=new.post_id and user_id=new.user_id;
 return new;
end $$;
drop trigger if exists meetup_record_withdrawal on public.meetup_participants;
create trigger meetup_record_withdrawal after insert or delete on public.meetup_participants
 for each row execute function public.meetup_record_withdrawal();
create or replace function public.my_meetups() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); result jsonb;
begin
 if u is null then raise exception '로그인이 필요해요.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(data order by upcoming desc,event_at),'[]'::jsonb) into result from (
  select p.event_at, not p.meetup_cancelled and not mine.cancelled and p.event_at>now() as upcoming,
   jsonb_build_object('id',p.id,'title',p.title,'event_at',p.event_at,'duration_minutes',p.duration_minutes,
    'meetup_topic',p.meetup_topic,'meetup_cancelled',p.meetup_cancelled,'participation_cancelled',mine.cancelled,
    'facility_name',f.name,'is_host',p.author_id=u,'max_participants',p.max_participants,
    'count',(select count(*) from public.meetup_participants mp where mp.post_id=p.id),
    'participants',case when mine.cancelled then '[]'::jsonb else coalesce((
     select jsonb_agg(jsonb_build_object('nickname',coalesce(pp.nickname,'탈퇴한 이웃'),
       'is_me',mp.user_id=u,'is_host',mp.user_id=p.author_id) order by (mp.user_id=p.author_id) desc,mp.joined_at)
      from public.meetup_participants mp left join public.public_profiles pp on pp.id=mp.user_id
      where mp.post_id=p.id),'[]'::jsonb) end) data
  from (
   select post_id,false cancelled from public.meetup_participants where user_id=u
   union all
   select w.post_id,true from public.meetup_withdrawals w where w.user_id=u and not exists(
    select 1 from public.meetup_participants mp where mp.post_id=w.post_id and mp.user_id=u)
  ) mine join public.posts p on p.id=mine.post_id and p.category='동네모임'
  left join public.facilities f on f.id=p.facility_id
  where (p.author_id=u or not public.post_is_hidden(p.id))
   and not exists(select 1 from public.user_blocks b where b.user_id=u and b.blocked_id=p.author_id)
 ) rows;
 return result;
end $$;
revoke all on function public.meetup_record_withdrawal() from public,anon,authenticated;
revoke all on function public.my_meetups() from public,anon;
grant execute on function public.my_meetups() to authenticated;
commit;
notify pgrst,'reload schema';
