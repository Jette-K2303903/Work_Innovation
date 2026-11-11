-- driver_locations (기사 마지막 위치) 표 다시 만들기
-- Supabase → SQL Editor 에 전체 붙여넣고 Run (여러 번 실행해도 안전, 다른 표는 건드리지 않음)
create table if not exists public.driver_locations (
    driver_name   text primary key,
    delivery_date text,
    vehicle_no    text,
    lat           double precision,
    lng           double precision,
    accuracy      real,
    device_at     timestamptz,
    consent_at    timestamptz,
    status        text,                      -- on / denied / unavailable / timeout / declined / unsupported
    updated_at    timestamptz not null default now()
);
alter table public.driver_locations add column if not exists status text;

alter table public.driver_locations enable row level security;
drop policy if exists "locations select" on public.driver_locations;
create policy "locations select" on public.driver_locations for select to anon, authenticated using (true);
drop policy if exists "locations insert" on public.driver_locations;
create policy "locations insert" on public.driver_locations for insert to anon, authenticated with check (true);
drop policy if exists "locations update" on public.driver_locations;
create policy "locations update" on public.driver_locations for update to anon, authenticated using (true) with check (true);

grant select, insert, update on public.driver_locations to anon, authenticated;
notify pgrst, 'reload schema';
