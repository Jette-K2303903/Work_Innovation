-- =====================================================================
-- 특이사항 관리 (실시간 협업 시트) 저장 표
-- Supabase > SQL Editor 에 전체 붙여넣고 Run 한 번이면 됩니다. (여러 번 실행해도 안전)
-- =====================================================================
create table if not exists public.issue_sheet_rows (
  id             bigserial primary key,
  issue_date     date default current_date,   -- 일자
  store_code     text,                         -- 매장코드
  store_name     text,                         -- 매장명 (매장코드 입력 시 자동)
  product_code   text,                         -- 제품코드
  product_name   text,                         -- 제품명 (제품코드 입력 시 자동)
  inbound_center text,                         -- 입고센터 (자동)
  unit           text,                         -- 단위 (자동)
  qty            text,                         -- 수량
  issue_type     text,                         -- 문제 유형
  detail         text,                         -- 상세 내용
  action_taken   text,                         -- 조치 내용
  status         text default '접수',          -- 접수 / 처리중 / 완료
  created_by     text,                         -- 작성자 (사무실 연락처 성명)
  updated_by     text,                         -- 마지막 수정자
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);
create index if not exists issue_sheet_rows_store_idx   on public.issue_sheet_rows (store_code);
create index if not exists issue_sheet_rows_product_idx on public.issue_sheet_rows (product_code);
create index if not exists issue_sheet_rows_date_idx    on public.issue_sheet_rows (issue_date);

alter table public.issue_sheet_rows enable row level security;
drop policy if exists issue_sheet_rows_select on public.issue_sheet_rows;
drop policy if exists issue_sheet_rows_insert on public.issue_sheet_rows;
drop policy if exists issue_sheet_rows_update on public.issue_sheet_rows;
drop policy if exists issue_sheet_rows_delete on public.issue_sheet_rows;
create policy issue_sheet_rows_select on public.issue_sheet_rows for select to anon, authenticated using (true);
create policy issue_sheet_rows_insert on public.issue_sheet_rows for insert to anon, authenticated with check (true);
create policy issue_sheet_rows_update on public.issue_sheet_rows for update to anon, authenticated using (true) with check (true);
create policy issue_sheet_rows_delete on public.issue_sheet_rows for delete to anon, authenticated using (true);
grant select, insert, update, delete on public.issue_sheet_rows to anon, authenticated;
grant usage, select on sequence public.issue_sheet_rows_id_seq to anon, authenticated;

-- 다른 사람이 입력한 내용이 바로 보이도록 실시간 등록 (이미 등록돼 있으면 건너뜀)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'issue_sheet_rows') then
    alter publication supabase_realtime add table public.issue_sheet_rows;
  end if;
end $$;
alter table public.issue_sheet_rows replica identity full;

notify pgrst, 'reload schema';
