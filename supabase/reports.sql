-- Run once in the SQL Editor (after all earlier files).
-- 신고하기: posts(게시글·동네모임)와 comments(댓글) 신고 저장 + 3건 이상이면 숨김.

-- 1) 신고 테이블. 한 줄 = 한 사람의 신고 1건. post_id / comment_id 중
--    정확히 하나만 채워진다.
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  post_id uuid references public.posts (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  reason text not null check (reason in ('욕설·비방', '광고', '사기 의심', '기타')),
  created_at timestamptz not null default now(),
  check ((post_id is null) <> (comment_id is null)),
  -- 같은 사람이 같은 글/댓글을 두 번 신고할 수 없게 (null은 서로 겹치지
  -- 않는 것으로 취급되므로 두 unique가 서로 방해하지 않는다).
  unique (reporter_id, post_id),
  unique (reporter_id, comment_id)
);

create index reports_post_id_idx on public.reports (post_id);
create index reports_comment_id_idx on public.reports (comment_id);

alter table public.reports enable row level security;

-- 신고는 본인 이름으로만 넣을 수 있고, 본인이 한 신고만 볼 수 있다.
-- 수정·삭제 정책은 일부러 만들지 않는다(신고 취소·조작 불가).
-- 팀은 대시보드(관리자 권한)에서 모든 신고를 볼 수 있다.
create policy "Users can file their own reports"
on public.reports for insert
with check (auth.uid() = reporter_id);

create policy "Users can view their own reports"
on public.reports for select
using (auth.uid() = reporter_id);

-- 2) 신고 수 확인 함수. security definer라서 "본인 신고만 보기" 제한과
--    상관없이 전체 신고 수를 세지만, 돌려주는 건 참/거짓 하나뿐이다.
create or replace function public.post_is_hidden(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select count(*) >= 3 from public.reports where post_id = target_id;
$$;

create or replace function public.comment_is_hidden(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select count(*) >= 3 from public.reports where comment_id = target_id;
$$;

-- 3) 읽기 권한을 "신고 3건 미만이거나 내가 쓴 것"으로 교체.
--    글쓴이 본인에게는 계속 보여서 수정·삭제할 수 있다.
drop policy if exists "Signed-in users can view posts" on public.posts;
create policy "Signed-in users can view posts"
on public.posts for select
using (
  auth.uid() is not null
  and (author_id = auth.uid() or not public.post_is_hidden(id))
);

drop policy if exists "Signed-in users can view comments" on public.comments;
create policy "Signed-in users can view comments"
on public.comments for select
using (
  auth.uid() is not null
  and (author_id = auth.uid() or not public.comment_is_hidden(id))
);

-- 4) 팀이 대시보드에서 보기 편한 신고 모아보기.
--    security_invoker라서 앱 사용자가 열면 RLS 때문에 본인 신고만 보이고,
--    대시보드(관리자)에서는 전부 보인다. 그래도 앱에서는 쓸 일이 없으니
--    앱 계정의 접근은 아예 막아둔다.
create view public.report_summary
with (security_invoker = true)
as
select
  r.created_at as 신고일시,
  case when r.post_id is not null then '게시글' else '댓글' end as 종류,
  coalesce(p.title, c.content) as 신고된_내용,
  r.reason as 사유,
  reporter.nickname as 신고한_사람,
  coalesce(p_author.nickname, c_author.nickname) as 작성자,
  count(*) over (partition by r.post_id, r.comment_id) as 누적_신고수,
  r.post_id,
  r.comment_id
from public.reports r
left join public.posts p on p.id = r.post_id
left join public.comments c on c.id = r.comment_id
left join public.profiles reporter on reporter.id = r.reporter_id
left join public.profiles p_author on p_author.id = p.author_id
left join public.profiles c_author on c_author.id = c.author_id
order by r.created_at desc;

revoke all on public.report_summary from anon, authenticated;
