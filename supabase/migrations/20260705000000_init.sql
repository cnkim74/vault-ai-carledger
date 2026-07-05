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

-- 시드 데이터 없음: 실제 사용 데이터만 유지 (목업 차량/기록 제거).
-- 차량은 앱의 '차고 > 차량 추가'로 등록하고, 기록은 '+'로 입력합니다.
