-- 데모 단계: 익명 기록 추가 허용 (인증 도입 시 사용자별 정책으로 교체)
create policy "records: anon insert" on records for insert with check (true);
