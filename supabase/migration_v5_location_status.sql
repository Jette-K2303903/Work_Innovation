-- 위치가 안 잡히는 이유(권한 차단 · GPS 꺼짐 · 미동의 등)를 실시간 대시보드에 표시하기 위한 칸
-- Supabase → SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
alter table public.driver_locations add column if not exists status text;
