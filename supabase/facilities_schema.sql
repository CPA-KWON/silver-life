-- Run this once in the Supabase project's SQL Editor, after schema.sql and
-- community_schema.sql.

-- Shared reference table for real-world places (경로당/복지관 등). Rows are
-- created either by a bulk import from public data, or lazily the first
-- time a user checks in or picks a location for a meetup post.
create table public.facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null,
  lat double precision not null,
  lng double precision not null,
  category text,
  telephone text,
  created_at timestamptz not null default now(),
  unique (name, address)
);

alter table public.facilities enable row level security;

create policy "Signed-in users can view facilities"
on public.facilities for select
using (auth.uid() is not null);

create policy "Signed-in users can add facilities"
on public.facilities for insert
with check (auth.uid() is not null);

-- Favorites: a user's saved facilities, shown on the home tab.
create table public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  address text not null,
  telephone text,
  lat double precision not null,
  lng double precision not null,
  category text,
  created_at timestamptz not null default now(),
  unique (user_id, name, address)
);

alter table public.favorites enable row level security;

create policy "Users can view own favorites"
on public.favorites for select
using (auth.uid() = user_id);

create policy "Users can add own favorites"
on public.favorites for insert
with check (auth.uid() = user_id);

create policy "Users can delete own favorites"
on public.favorites for delete
using (auth.uid() = user_id);

-- Check-ins: "나 여기 있음" presence at a facility. Only a count is ever
-- shown in the app — never who specifically is checked in.
create table public.checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  facility_id uuid not null references public.facilities (id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  unique (user_id, facility_id)
);

alter table public.checkins enable row level security;

create policy "Signed-in users can view checkins"
on public.checkins for select
using (auth.uid() is not null);

create policy "Users can check themselves in"
on public.checkins for insert
with check (auth.uid() = user_id);

create policy "Users can check themselves out"
on public.checkins for delete
using (auth.uid() = user_id);

-- Meetup posts (기능 5): optional event fields on a post, plus the facility
-- it's tied to.
alter table public.posts
  add column event_at timestamptz,
  add column facility_id uuid references public.facilities (id);
