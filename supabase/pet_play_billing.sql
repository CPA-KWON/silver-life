-- Server-only verified purchase grants. Apply after pet_expansion.sql.
begin;
create table if not exists public.pet_play_purchases(
 token text primary key,user_id uuid not null references auth.users on delete cascade,
 product text not null references public.pet_item_catalog(product_id),item text not null references public.pet_item_catalog(id),
 order_id text not null,revoked boolean not null default false,created_at timestamptz not null default now(),checked_at timestamptz not null default now()
);
alter table public.pet_play_purchases enable row level security;
-- Tokens are not exposed even to the purchasing client. Support UI reads a safe RPC.
revoke all on public.pet_play_purchases from public,anon,authenticated;
create or replace function public.pet_grant_play_purchase(p_user uuid,p_token text,p_product text,p_order text) returns void
language plpgsql security definer set search_path='' as $$
declare c public.pet_item_catalog;old public.pet_play_purchases;
begin
 if p_user is null or length(p_token) not between 5 and 4096 then raise exception 'invalid purchase';end if;
 perform 1 from public.point_wallets where user_id=p_user for update;
 select * into c from public.pet_item_catalog where product_id=p_product and source='play' and enabled;
 if not found then raise exception 'invalid product';end if;
 if not exists(select 1 from public.pet_companions where user_id=p_user and species=c.species) then raise exception 'incompatible pet';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_token,0));
 select * into old from public.pet_play_purchases where token=p_token for update;
 if found then
  if old.user_id<>p_user or old.product<>p_product or old.revoked then raise exception 'purchase already bound or revoked';end if;
  update public.pet_play_purchases set checked_at=now() where token=p_token;
  return;
 end if;
 -- Preserve independent inventory ownership when a duplicate item is bought on another token.
 if exists(select 1 from public.pet_inventory where user_id=p_user and item=c.id) then raise exception 'already owned';end if;
 insert into public.pet_play_purchases(token,user_id,product,item,order_id) values(p_token,p_user,p_product,c.id,p_order);
 insert into public.pet_inventory(user_id,item) values(p_user,c.id) on conflict do nothing;
 insert into public.pet_history(user_id,reference,title,kind) values(p_user,'play:'||p_order,c.name||'를 구매했어요','purchase') on conflict do nothing;
end $$;
create or replace function public.pet_revoke_play_purchase(p_token text) returns void
language plpgsql security definer set search_path='' as $$
declare purchase public.pet_play_purchases;
begin
 select * into purchase from public.pet_play_purchases where token=p_token;
 if not found then return;end if;
 perform 1 from public.point_wallets where user_id=purchase.user_id for update;
 perform pg_advisory_xact_lock(hashtextextended(p_token,0));
 update public.pet_play_purchases set revoked=true,checked_at=now() where token=p_token;
 if not exists(select 1 from public.pet_play_purchases where user_id=purchase.user_id and item=purchase.item and not revoked) then
  delete from public.pet_inventory where user_id=purchase.user_id and item=purchase.item;
 end if;
end $$;
create or replace function public.pet_purchase_history() returns jsonb
language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'date',p.created_at,'revoked',p.revoked) order by p.created_at desc),'[]'::jsonb)
 from public.pet_play_purchases p join public.pet_item_catalog c on c.id=p.item where p.user_id=auth.uid();
$$;
revoke all on function public.pet_grant_play_purchase(uuid,text,text,text),public.pet_revoke_play_purchase(text),public.pet_purchase_history() from public,anon,authenticated;
grant execute on function public.pet_grant_play_purchase(uuid,text,text,text),public.pet_revoke_play_purchase(text) to service_role;
grant execute on function public.pet_purchase_history() to authenticated;
-- Remains disabled until real Play products, refunds/reconciliation and internal testing are ready.
insert into public.pet_config values('play_enabled','false') on conflict do nothing;
commit;
