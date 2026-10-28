-- Private photo bucket. Apply neighborhood_mockups.sql first.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('neighborhood-media','neighborhood-media',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists neighborhood_media_upload on storage.objects;
create policy neighborhood_media_upload on storage.objects for insert to authenticated with check(bucket_id='neighborhood-media' and (storage.foldername(name))[1]=auth.uid()::text and (storage.foldername(name))[2] in('posts','avatars'));
drop policy if exists neighborhood_media_read on storage.objects;
create policy neighborhood_media_read on storage.objects for select to authenticated using(bucket_id='neighborhood-media' and (
 (storage.foldername(name))[1]=auth.uid()::text or (storage.foldername(name))[2]='avatars' or
 exists(select 1 from public.posts p where name=any(p.image_paths))));
drop policy if exists neighborhood_media_remove on storage.objects;
create policy neighborhood_media_remove on storage.objects for delete to authenticated using(bucket_id='neighborhood-media' and (storage.foldername(name))[1]=auth.uid()::text);
-- Caller cannot attach another account's private avatar.
create or replace function public.neighborhood_validate_avatar() returns trigger language plpgsql set search_path='' as $$begin
 if new.avatar_path is not null and new.avatar_path not like new.id::text||'/avatars/%' then raise exception '사진 경로를 확인해 주세요'; end if;return new;end $$;
drop trigger if exists neighborhood_avatar on public.profiles;
create trigger neighborhood_avatar before insert or update on public.profiles for each row execute function public.neighborhood_validate_avatar();
create or replace function public.delete_my_account() returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();begin
 if uid is null then raise exception '로그인이 필요해요' using errcode='42501';end if;
 if exists(select 1 from storage.objects where bucket_id='neighborhood-media' and (storage.foldername(name))[1]=uid::text) then raise exception '먼저 첨부 사진을 정리한 뒤 다시 시도해 주세요';end if;
 delete from auth.users where id=uid;
end $$;
revoke all on function public.delete_my_account() from public,anon;
grant execute on function public.delete_my_account() to authenticated;
commit;
