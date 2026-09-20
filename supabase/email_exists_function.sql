-- Run once in the SQL Editor.
-- Lets the signup form show an inline "이미 가입된 이메일입니다" check before
-- submitting, without exposing auth.users to the client directly (PostgREST
-- never exposes the auth schema, and RLS can't apply to it from here anyway).
-- security definer runs this as the function owner, who has access to
-- auth.users, while callers only ever get a single boolean back.
create or replace function public.email_exists(check_email text)
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from auth.users where lower(email) = lower(trim(check_email))
  );
$$;

grant execute on function public.email_exists(text) to anon, authenticated;
