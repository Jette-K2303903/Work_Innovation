-- =====================================================================
-- 특이사항 관리 : 채팅 · 수정 기록 자동 정리 함수
-- 데이터 관리 > 유지기간에서 정한 일수(기본 60일)보다 오래된 채팅 메시지와 수정 기록을 지웁니다.
-- 사무실 담당자가 로그인할 때 사이트가 자동으로 실행합니다.
-- Supabase > SQL Editor 에 전체 붙여넣고 Run 한 번 (여러 번 실행해도 안전)
-- ※ '특이사항관리_채팅_기록_DB.sql' 을 먼저 실행한 상태여야 합니다.
-- =====================================================================
create or replace function public.purge_issue_sheet_history(keep_days int default 60)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  d int := greatest(1, least(coalesce(keep_days, 60), 365));   -- 1~365일 사이로만
  m int; l int;
begin
  delete from public.issue_sheet_messages where created_at < now() - make_interval(days => d);
  get diagnostics m = row_count;
  delete from public.issue_sheet_logs where created_at < now() - make_interval(days => d);
  get diagnostics l = row_count;
  return json_build_object('keep_days', d, 'messages_deleted', m, 'logs_deleted', l);
end $$;

revoke all on function public.purge_issue_sheet_history(int) from public;
grant execute on function public.purge_issue_sheet_history(int) to anon, authenticated;

notify pgrst, 'reload schema';
