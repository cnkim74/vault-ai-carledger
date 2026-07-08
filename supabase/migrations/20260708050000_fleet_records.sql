create table if not exists fleet_records (
  id uuid primary key default gen_random_uuid(),
  fleet_id uuid not null references fleets(id) on delete cascade,
  fleet_vehicle_id uuid not null references fleet_vehicles(id) on delete cascade,
  kind text not null default 'fuel',
  title text, amount_won int, distance_km numeric, odometer_km int,
  occurred_at timestamptz not null default now(), memo text,
  created_at timestamptz not null default now()
);
create index if not exists fleet_records_fleet_idx on fleet_records(fleet_id);
create index if not exists fleet_records_vehicle_idx on fleet_records(fleet_vehicle_id);
alter table fleet_records enable row level security;
create policy "fleet_records: anon all" on fleet_records for all using (true) with check (true);
