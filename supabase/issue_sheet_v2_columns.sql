-- =====================================================================
-- 특이사항 관리 : 새 양식 칸 추가
-- (배송일 · 메인센터 · 고객사코드 · 고객사명 · 거래처코드 · 거래처명 · 제품코드 · 온도 · 단위
--  · 재고타입 · 수량 · 내용 · 상세내용 · 주체 · 귀책 · 입고 · 자료등록)
-- Supabase > SQL Editor 에 전체 붙여넣고 Run 한 번 (여러 번 실행해도 안전)
-- ※ '특이사항관리_DB.sql' 을 먼저 실행한 상태여야 합니다. 기존에 입력한 내용은 지워지지 않습니다.
-- =====================================================================
alter table public.issue_sheet_rows
  add column if not exists delivery_date date,     -- 배송일
  add column if not exists main_center   text,     -- 메인센터 (자동)
  add column if not exists client_code   text,     -- 고객사코드 (자동)
  add column if not exists client_name   text,     -- 고객사명 (자동)
  add column if not exists temperature   text,     -- 온도 (자동)
  add column if not exists stock_type    text,     -- 재고타입 (자동)
  add column if not exists content       text,     -- 내용
  add column if not exists subject       text,     -- 주체
  add column if not exists fault         text,     -- 귀책
  add column if not exists inbound       text,     -- 입고
  add column if not exists data_reg      text;     -- 자료등록
-- (거래처코드 store_code · 거래처명 store_name · 제품코드 product_code · 단위 unit · 수량 qty · 상세내용 detail 은 이미 있음)

-- 예전 양식의 '일자'·'문제 유형'을 새 칸으로 옮겨 둠 (비어 있는 경우만)
update public.issue_sheet_rows set delivery_date = issue_date where delivery_date is null and issue_date is not null;
update public.issue_sheet_rows set content = issue_type where (content is null or content = '') and issue_type is not null and issue_type <> '';

create index if not exists issue_sheet_rows_delivery_idx on public.issue_sheet_rows (delivery_date);
notify pgrst, 'reload schema';
