-- Run once in the SQL Editor.
-- Adds region columns to facilities (derived from the address's first two
-- space-separated tokens, e.g. "서울특별시 강남구 ..." -> sido="서울특별시",
-- sigungu="강남구") so meetups can be filtered by WHERE they actually are,
-- not by the poster's home district.

alter table public.facilities
  add column region_sido text,
  add column region_sigungu text;

update public.facilities
set
  region_sido = split_part(address, ' ', 1),
  region_sigungu = split_part(address, ' ', 2)
where region_sido is null;

-- A meetup must have a real place — the app already requires this in the
-- form; this is the DB-level backstop.
alter table public.posts
  add constraint meetup_requires_facility
  check (category <> '동네모임' or facility_id is not null);
