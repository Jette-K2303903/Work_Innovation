-- =====================================================================
-- 특이사항 관리 : 채팅 · @태그 알림 · 수정 기록 표
-- Supabase > SQL Editor 에 전체 붙여넣고 Run 한 번 (여러 번 실행해도 안전)
-- ※ 먼저 '특이사항관리_DB.sql' 을 실행한 상태여야 합니다.
-- =====================================================================

-- 1) 채팅 메시지
create table if not exists public.issue_sheet_messages (
  id         bigserial primary key,
  author     text not null,                 -- 보낸 사람 (사무실 연락처 성명)
  body       text not null,                 -- 내용
  mentions   text[] default '{}',           -- @태그된 사람들
  created_at timestamptz default now()
);
create index if not exists issue_sheet_messages_mentions_idx on public.issue_sheet_messages using gin (mentions);

-- 2) 사람별 태그 알림 읽은 시각 (다른 컴퓨터에서 접속해도 알림 숫자가 같게)
create table if not exists public.issue_sheet_reads (
  user_name    text primary key,
  last_read_at timestamptz default now()
);

-- 3) 수정 기록 (누가 · 언제 · 어떤 행의 · 무엇을 · 무엇에서 무엇으로)
create table if not exists public.issue_sheet_logs (
  id         bigserial primary key,
  actor      text,          -- 수정한 사람
  action     text,          -- 추가 / 수정 / 삭제
  row_id     bigint,        -- 특이사항 행 번호
  row_label  text,          -- 매장 / 제품 (알아보기 쉽게)
  field_key  text,
  field      text,          -- 바뀐 칸 이름
  old_value  text,
  new_value  text,
  created_at timestamptz default now()
);
create index if not exists issue_sheet_logs_row_idx on public.issue_sheet_logs (row_id);

-- 권한 (사이트에서 읽고 쓸 수 있도록) — 수정 기록은 지우거나 고칠 수 없게 '추가'만 허용
alter table public.issue_sheet_messages enable row level security;
alter table public.issue_sheet_reads    enable row level security;
alter table public.issue_sheet_logs     enable row level security;

drop policy if exists ism_select on public.issue_sheet_messages;
drop policy if exists ism_insert on public.issue_sheet_messages;
create policy ism_select on public.issue_sheet_messages for select to anon, authenticated using (true);
create policy ism_insert on public.issue_sheet_messages for insert to anon, authenticated with check (true);

drop policy if exists isr_select on public.issue_sheet_reads;
drop policy if exists isr_insert on public.issue_sheet_reads;
drop policy if exists isr_update on public.issue_sheet_reads;
create policy isr_select on public.issue_sheet_reads for select to anon, authenticated using (true);
create policy isr_insert on public.issue_sheet_reads for insert to anon, authenticated with check (true);
create policy isr_update on public.issue_sheet_reads for update to anon, authenticated using (true) with check (true);

drop policy if exists isl_select on public.issue_sheet_logs;
drop policy if exists isl_insert on public.issue_sheet_logs;
create policy isl_select on public.issue_sheet_logs for select to anon, authenticated using (true);
create policy isl_insert on public.issue_sheet_logs for insert to anon, authenticated with check (true);

grant select, insert on public.issue_sheet_messages to anon, authenticated;
grant select, insert, update on public.issue_sheet_reads to anon, authenticated;
grant select, insert on public.issue_sheet_logs to anon, authenticated;
grant usage, select on sequence public.issue_sheet_messages_id_seq to anon, authenticated;
grant usage, select on sequence public.issue_sheet_logs_id_seq to anon, authenticated;

-- 실시간 등록 (새 메시지 · 새 기록이 바로 보이도록)
do $$
declare t text;
begin
  foreach t in array array['issue_sheet_messages','issue_sheet_logs'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
