-- Run once in the SQL Editor. Splits profiles.region ("시도 시군구") into
-- two columns so posts can be filtered by either granularity (needed for
-- the community/meetup region scope: 전체 / 시도 단위 / 시군구 단위).

alter table public.profiles
  add column region_sido text,
  add column region_sigungu text;

update public.profiles
set
  region_sido = split_part(region, ' ', 1),
  region_sigungu = split_part(region, ' ', 2)
where region is not null;

alter table public.profiles
  alter column region_sido set not null,
  alter column region_sigungu set not null,
  drop column region;

-- Update the sign-up trigger to populate the two new columns directly
-- (the client now sends region_sido/region_sigungu separately instead of
-- one combined "region" string).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nickname, name, region_sido, region_sigungu, birth_year)
  values (
    new.id,
    new.raw_user_meta_data ->> 'nickname',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'region_sido',
    new.raw_user_meta_data ->> 'region_sigungu',
    (new.raw_user_meta_data ->> 'birth_year')::int
  );
  return new;
end;
$$;
