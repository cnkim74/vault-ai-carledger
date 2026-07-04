-- VAULT AI 차계부 — 초기 스키마
-- Supabase SQL Editor에 붙여넣거나 `supabase db push`로 적용하세요.

-- 차량
create table if not exists vehicles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  plate text,
  fuel_type text not null default '전기차',
  battery int not null default 82 check (battery between 0 and 100),
  odometer_km int not null default 0,
  lease_limit_km int,
  lease_driven_km int,
  created_at timestamptz not null default now()
);

-- 기록 (충전 / 주행 / 정비)
create table if not exists records (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  kind text not null check (kind in ('charge', 'drive', 'maintenance')),
  title text not null,
  occurred_at timestamptz not null default now(),
  amount_won int,
  distance_km numeric,
  duration_min int,
  location text,
  tag text,
  ai_logged boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists records_vehicle_occurred_idx
  on records (vehicle_id, occurred_at desc);

-- RLS: 데모 단계 — 익명 읽기 허용 (인증 도입 시 정책 교체)
alter table vehicles enable row level security;
alter table records enable row level security;

create policy "vehicles: anon read" on vehicles for select using (true);
create policy "records: anon read" on records for select using (true);

-- 시드 데이터 (디자인 목업과 동일)
insert into vehicles (name, plate, fuel_type, battery, odometer_km, lease_limit_km, lease_driven_km)
values ('Model Y Long Range', '62가 3817', '전기차', 82, 24318, 20000, 17200);

insert into records (vehicle_id, kind, title, occurred_at, amount_won, distance_km, duration_min, location, tag, ai_logged)
select v.id, r.kind, r.title, r.occurred_at, r.amount_won, r.distance_km, r.duration_min, r.location, r.tag, r.ai_logged
from vehicles v,
(values
  ('charge', '초급속 충전 · 42kWh', now()::date + interval '7 hours 12 minutes', 14900, null::numeric, null::int, '이마트 성수', null, true),
  ('drive', '주행 일지 · 서울 → 판교', now()::date - interval '1 day' + interval '8 hours 40 minutes', null, 38.2, 21, null, '출퇴근', false),
  ('maintenance', '엔진오일 교체 알림', now()::date - interval '2 days', null, null, null, '세컨카', '2,000km 남음', false)
) as r(kind, title, occurred_at, amount_won, distance_km, duration_min, location, tag, ai_logged)
where v.plate = '62가 3817';
