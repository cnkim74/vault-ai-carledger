-- 데모 단계: 익명 차량 추가 허용 (인증 도입 시 교체)
create policy "vehicles: anon insert" on vehicles for insert with check (true);
