-- Run this once in the Supabase project's SQL Editor
-- (Dashboard > SQL Editor > New query > paste > Run).

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null unique,
  name text not null,
  region text not null,
  birth_year integer not null check (
    birth_year between 1900 and extract(year from now())::int
  ),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view own profile"
on public.profiles for select
using (auth.uid() = id);

create policy "Users can insert own profile"
on public.profiles for insert
with check (auth.uid() = id);

create policy "Users can update own profile"
on public.profiles for update
using (auth.uid() = id);

-- Auto-creates a profiles row right after sign-up, reading the extra
-- fields (nickname/name/region/birth_year) passed in supabase.auth.signUp's
-- `data` argument. If the nickname is already taken, this raises a unique
-- violation and the sign-up call fails with that error.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nickname, name, region, birth_year)
  values (
    new.id,
    new.raw_user_meta_data ->> 'nickname',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'region',
    (new.raw_user_meta_data ->> 'birth_year')::int
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
