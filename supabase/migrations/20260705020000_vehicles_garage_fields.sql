-- 차고 기능: 차량 상세 필드 추가
alter table vehicles
  add column if not exists ownership text not null default 'purchase' check (ownership in ('purchase','lease','rent')),
  add column if not exists maker text,
  add column if not exists model text,
  add column if not exists year int,
  add column if not exists purchase_price_won bigint,
  add column if not exists monthly_fee_won int,
  add column if not exists contract_end date;

-- 데모 단계: 익명 차량 수정 허용 (인증 도입 시 교체)
create policy "vehicles: anon update" on vehicles for update using (true) with check (true);
