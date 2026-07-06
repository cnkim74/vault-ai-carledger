-- 기록 수정/삭제 허용 (anon)
create policy "records: anon update" on records for update using (true) with check (true);
create policy "records: anon delete" on records for delete using (true);
