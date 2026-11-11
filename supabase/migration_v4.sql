-- =====================================================================
--  Delivery Connect · 기사님 페이지 서버 기록용 마이그레이션 (v4)
--  대상 : work-innovation.onrender.com 이 쓰는 Supabase 프로젝트 (yfnwboangwvwbvifhxdl)
--  사용 : Supabase → SQL Editor 에 전체 붙여넣고 Run (여러 번 실행해도 안전)
--
--  driver/index.html 은 아래 컬럼/테이블이 없으면 그 항목만 건너뛰고 동작합니다.
--  실행하는 순간부터 하차 완료 · 배송 순서 · 정확한 시각 · 이력 · 서명이 서버에 쌓입니다.
-- =====================================================================

-- 1) dispatch_data : 배송 진행 기록 (기존 업로드 컬럼은 건드리지 않음)
alter table public.dispatch_data
    add column if not exists route_order  integer,                        -- 기사가 정한 배송 순서 (1부터). 관리자가 바꾸면 기사 화면에 즉시 반영
    add column if not exists is_completed boolean not null default false,  -- 하차 완료 여부
    add column if not exists started_at   text,                           -- 'HH시 MM분 시작'  (표시용)
    add column if not exists arrived_at   text,                           -- 'HH시 MM분 도착'  (표시용)
    add column if not exists completed_at text,                           -- 'HH시 MM분 완료'  (표시용)
    add column if not exists started_ts   timestamptz,                    -- 배송 시작 정확한 시각
    add column if not exists arrived_ts   timestamptz,                    -- 매장 도착 정확한 시각
    add column if not exists completed_ts timestamptz;                    -- 하차 완료 정확한 시각

create index if not exists dispatch_data_date_driver_idx
    on public.dispatch_data (delivery_date, driver_name);


-- 2) driver_event_logs : 배송 시작 · 매장 도착 · 하차 완료 · 순서 변경 이력 (누적 보관)
--    → 매장별 이동/체류 시간 분석, 다음 매장 도착 예상시간 계산에 사용
create table if not exists public.driver_event_logs (
    id            bigserial primary key,
    delivery_date text,                        -- dispatch_data.delivery_date (YYYY-MM-DD)
    driver_name   text        not null,
    vehicle_no    text,
    business_code text,                        -- 매장코드 (배송 시작 · 순서 변경은 null)
    business_name text,
    event_type    text        not null check (event_type in ('start', 'arrive', 'unload', 'reorder')),
    device_at     timestamptz not null,        -- 기사가 버튼을 누른 시각 (오프라인 후 전송돼도 원래 시각 유지)
    payload       jsonb,                       -- 관리자가 대신 처리하면 {"by": "admin"} 포함. 예) unload: {"arrived_ts": "...", "dwell_min": 7}, reorder: {"order": ["A001", ...]}
    created_at    timestamptz not null default now()
);
-- 이벤트 종류 : 관리자가 기록을 취소한 'undo' 포함 (이전 버전 SQL 을 이미 실행했어도 안전하게 갱신)
alter table public.driver_event_logs drop constraint if exists driver_event_logs_event_type_check;
alter table public.driver_event_logs add constraint driver_event_logs_event_type_check
    check (event_type in ('start', 'arrive', 'unload', 'reorder', 'undo'));
create index if not exists driver_event_logs_lookup_idx on public.driver_event_logs (delivery_date, driver_name, device_at);
create index if not exists driver_event_logs_store_idx  on public.driver_event_logs (business_code, event_type, device_at);

alter table public.driver_event_logs enable row level security;
drop policy if exists "driver logs insert" on public.driver_event_logs;
create policy "driver logs insert" on public.driver_event_logs for insert to anon, authenticated with check (true);
drop policy if exists "driver logs select" on public.driver_event_logs;
create policy "driver logs select" on public.driver_event_logs for select to anon, authenticated using (true);
-- (수정·삭제 정책 없음 → 이력 위변조 불가)


-- 3) driver_agreements : 시스템 사용 동의 및 보안서약 서명 기록 (기사별 최신 1건)
--    없으면 서명은 각 기사 휴대폰에만 저장됩니다.
create table if not exists public.driver_agreements (
    driver_name     text primary key,
    sign_url        text,          -- 서명 이미지 주소 (signatures 저장소)
    signed_at       text,          -- 'YYYY-MM-DD HH:MM'
    valid_until     timestamptz,
    last_signed_key text,          -- 동의 주기 키 (매일 19:00 기준)
    updated_at      timestamptz not null default now()
);
alter table public.driver_agreements enable row level security;
drop policy if exists "agreements select" on public.driver_agreements;
create policy "agreements select" on public.driver_agreements for select to anon, authenticated using (true);
drop policy if exists "agreements insert" on public.driver_agreements;
create policy "agreements insert" on public.driver_agreements for insert to anon, authenticated with check (true);
drop policy if exists "agreements update" on public.driver_agreements;
create policy "agreements update" on public.driver_agreements for update to anon, authenticated using (true) with check (true);

-- 서명 이미지 저장소 (signatures)
insert into storage.buckets (id, name, public)
values ('signatures', 'signatures', true)
on conflict (id) do nothing;
drop policy if exists "signatures upload" on storage.objects;
create policy "signatures upload" on storage.objects for insert to anon, authenticated with check (bucket_id = 'signatures');
drop policy if exists "signatures overwrite" on storage.objects;
create policy "signatures overwrite" on storage.objects for update to anon, authenticated using (bucket_id = 'signatures') with check (bucket_id = 'signatures');


-- 3-1) 도착 예상시간 (기사 화면에는 표시하지 않고 실시간 대시보드에서 사용)
alter table public.dispatch_data
    add column if not exists eta_ts      timestamptz,   -- 매장 도착 예정 시각
    add column if not exists eta_calc_ts timestamptz;   -- 그 예정 시각을 계산한 시각


-- 3-2) driver_locations : 위치 공유에 동의한 기사의 '마지막 위치 1건' (이동 경로 이력은 저장하지 않음)
create table if not exists public.driver_locations (
    driver_name   text primary key,
    delivery_date text,
    vehicle_no    text,
    lat           double precision,          -- 기사가 공유를 끄면 null 로 지워짐
    lng           double precision,
    accuracy      real,                      -- 오차 반경 (m)
    device_at     timestamptz,               -- 휴대폰에서 위치를 잡은 시각
    consent_at    timestamptz,               -- 기사가 위치 제공에 동의한 시각
    updated_at    timestamptz not null default now()
);
alter table public.driver_locations enable row level security;
drop policy if exists "locations select" on public.driver_locations;
create policy "locations select" on public.driver_locations for select to anon, authenticated using (true);
drop policy if exists "locations insert" on public.driver_locations;
create policy "locations insert" on public.driver_locations for insert to anon, authenticated with check (true);
drop policy if exists "locations update" on public.driver_locations;
create policy "locations update" on public.driver_locations for update to anon, authenticated using (true) with check (true);


-- 4) 실시간 반영 : 관리자가 dispatch_data 의 순서/상태를 바꾸면 기사 화면에 바로 반영
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dispatch_data'
    ) then
        alter publication supabase_realtime add table public.dispatch_data;
    end if;
end $$;


-- =====================================================================
--  참고 : 매장별 평균 이동 / 체류 시간 (도착 예상시간 계산의 기초 데이터)
-- =====================================================================
-- with ev as (
--     select driver_name, delivery_date, business_code, business_name, event_type, device_at,
--            lag(device_at)  over (partition by driver_name, delivery_date order by device_at) as prev_at,
--            lag(event_type) over (partition by driver_name, delivery_date order by device_at) as prev_type
--     from public.driver_event_logs
--     where event_type in ('start', 'arrive', 'unload')
-- )
-- select business_code, business_name,
--        round(avg(extract(epoch from device_at - prev_at) / 60) filter (where event_type = 'arrive' and prev_type in ('start', 'unload'))) as avg_travel_min,
--        round(avg(extract(epoch from device_at - prev_at) / 60) filter (where event_type = 'unload' and prev_type = 'arrive'))            as avg_dwell_min,
--        count(*) filter (where event_type = 'arrive') as visits
-- from ev
-- group by business_code, business_name
-- order by business_code;
