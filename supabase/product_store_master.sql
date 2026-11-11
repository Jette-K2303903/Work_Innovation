-- =====================================================================
-- 업로드 관리 : 제품정보 · 매장정보 저장 표 (누적 관리)
--  · 제품정보 : 제품코드 + 고객사 가 같으면 덮어쓰기, 다르면 새로 추가
--  · 매장정보 : 고객사코드 + 거래처코드 가 같으면 덮어쓰기, 다르면 새로 추가
-- 10만 행 이상이어도 코드 검색 · 이름 추천이 바로 되도록 색인을 함께 만듭니다.
-- Supabase > SQL Editor 에 전체 붙여넣고 Run 한 번 (여러 번 실행해도 안전)
-- =====================================================================
create extension if not exists pg_trgm;      -- 이름 일부로 찾는 검색(추천)을 빠르게

create table if not exists public.product_master (
  id               bigserial primary key,
  product_code     text not null,              -- A 제품코드
  product_name     text,                       -- B 제품명
  item_designation text,                       -- C 품목지정
  client           text not null default '',   -- D 고객사
  temperature      text,                       -- E 온도구분
  stock_type       text,                       -- F 재고타입
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  unique (product_code, client)
);
create index if not exists product_master_code_idx on public.product_master (product_code);
create index if not exists product_master_name_trgm on public.product_master using gin (product_name gin_trgm_ops);

create table if not exists public.store_master (
  id          bigserial primary key,
  client_code text not null default '',        -- A 고객사코드
  client_name text,                            -- B 고객사명
  store_code  text not null,                   -- C 거래처코드
  store_name  text,                            -- D 거래처명
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (client_code, store_code)
);
create index if not exists store_master_code_idx on public.store_master (store_code);
create index if not exists store_master_name_trgm on public.store_master using gin (store_name gin_trgm_ops);

-- 특이사항 관리의 이름 추천도 빠르게 (배차 · 주문 자료)
create index if not exists dispatch_data_bname_trgm on public.dispatch_data using gin (business_name gin_trgm_ops);
create index if not exists order_data_pname_trgm on public.order_data using gin (product_name gin_trgm_ops);

alter table public.product_master enable row level security;
alter table public.store_master   enable row level security;
do $$
declare t text;
begin
  foreach t in array array['product_master','store_master'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', t || '_select', t);
    execute format('create policy %I on public.%I for insert to anon, authenticated with check (true)', t || '_insert', t);
    execute format('create policy %I on public.%I for update to anon, authenticated using (true) with check (true)', t || '_update', t);
    execute format('create policy %I on public.%I for delete to anon, authenticated using (true)', t || '_delete', t);
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', t);
    execute format('grant usage, select on sequence public.%I to anon, authenticated', t || '_id_seq');
  end loop;
end $$;

notify pgrst, 'reload schema';
