create table if not exists fleets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  plan text not null default 'trial',
  created_at timestamptz not null default now()
);
create table if not exists fleet_vehicles (
  id uuid primary key default gen_random_uuid(),
  fleet_id uuid not null references fleets(id) on delete cascade,
  plate text, name text, model text, year int,
  category text not null default 'car',
  fuel text, odometer_km int not null default 0, lease_limit_km int,
  driver_name text, driver_phone text, memo text,
  status text not null default 'active',
  created_at timestamptz not null default now()
);
create index if not exists fleet_vehicles_fleet_idx on fleet_vehicles(fleet_id);
alter table fleets enable row level security;
alter table fleet_vehicles enable row level security;
create policy "fleets: anon all" on fleets for all using (true) with check (true);
create policy "fleet_vehicles: anon all" on fleet_vehicles for all using (true) with check (true);
