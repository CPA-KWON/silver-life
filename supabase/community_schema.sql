-- Run this once in the Supabase project's SQL Editor, after schema.sql.

-- author_id references profiles (not auth.users) so Supabase's PostgREST
-- can embed the author's nickname directly, e.g.
-- .from('posts').select('*, profiles(nickname)')
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  category text not null check (
    category in ('자유게시판', '동네모임', '건강정보', '나눔·도움요청')
  ),
  title text not null,
  content text not null,
  created_at timestamptz not null default now()
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

alter table public.posts enable row level security;
alter table public.comments enable row level security;

create policy "Signed-in users can view posts"
on public.posts for select
using (auth.uid() is not null);

create policy "Users can create their own posts"
on public.posts for insert
with check (auth.uid() = author_id);

create policy "Authors can update their own posts"
on public.posts for update
using (auth.uid() = author_id);

create policy "Authors can delete their own posts"
on public.posts for delete
using (auth.uid() = author_id);

create policy "Signed-in users can view comments"
on public.comments for select
using (auth.uid() is not null);

create policy "Users can create their own comments"
on public.comments for insert
with check (auth.uid() = author_id);

create policy "Authors can update their own comments"
on public.comments for update
using (auth.uid() = author_id);

create policy "Authors can delete their own comments"
on public.comments for delete
using (auth.uid() = author_id);
