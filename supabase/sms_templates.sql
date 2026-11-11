-- =====================================================================
-- 구간차량 관리 > 도착안내 문자 : 문자 양식(템플릿) 저장 표
-- Supabase > SQL Editor 에 전체 붙여넣고 Run 한 번 (여러 번 실행해도 안전)
-- '양식 구분명(category)'이 배차 업로드의 '문자템플릿' 값과 같으면 자동으로 매칭됩니다.
-- =====================================================================
create table if not exists public.sms_templates (
  id         bigserial primary key,
  category   text not null unique,   -- 양식 구분명 (배차 업로드의 문자템플릿 값과 같게)
  title      text,                   -- 발송 제목
  sender     text,                   -- 발신 번호
  body       text,                   -- 본문
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.sms_templates enable row level security;
drop policy if exists sms_templates_select on public.sms_templates;
drop policy if exists sms_templates_insert on public.sms_templates;
drop policy if exists sms_templates_update on public.sms_templates;
drop policy if exists sms_templates_delete on public.sms_templates;
create policy sms_templates_select on public.sms_templates for select to anon, authenticated using (true);
create policy sms_templates_insert on public.sms_templates for insert to anon, authenticated with check (true);
create policy sms_templates_update on public.sms_templates for update to anon, authenticated using (true) with check (true);
create policy sms_templates_delete on public.sms_templates for delete to anon, authenticated using (true);
grant select, insert, update, delete on public.sms_templates to anon, authenticated;
grant usage, select on sequence public.sms_templates_id_seq to anon, authenticated;

-- 배차 표에 양식지정 칸이 없다면 추가 (이미 있으면 건너뜀)
alter table public.dispatch_data add column if not exists format_type text;

notify pgrst, 'reload schema';
