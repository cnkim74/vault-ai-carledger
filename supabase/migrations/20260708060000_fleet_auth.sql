alter table fleets add column if not exists owner_id uuid;
alter table fleet_vehicles add column if not exists assigned_user_id uuid;
create table if not exists fleet_members (
  id uuid primary key default gen_random_uuid(),
  fleet_id uuid not null references fleets(id) on delete cascade,
  user_id uuid not null, role text not null default 'driver',
  created_at timestamptz not null default now(), unique (fleet_id, user_id)
);
alter table fleet_members enable row level security;
drop policy if exists "fleets: anon all" on fleets;
drop policy if exists "fleet_vehicles: anon all" on fleet_vehicles;
drop policy if exists "fleet_records: anon all" on fleet_records;
create policy "fleets: owner" on fleets for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "fleet_vehicles: owner" on fleet_vehicles for all
  using (fleet_id in (select id from fleets where owner_id = auth.uid()))
  with check (fleet_id in (select id from fleets where owner_id = auth.uid()));
create policy "fleet_records: owner" on fleet_records for all
  using (fleet_id in (select id from fleets where owner_id = auth.uid()))
  with check (fleet_id in (select id from fleets where owner_id = auth.uid()));
create policy "fleet_members: owner" on fleet_members for all
  using (fleet_id in (select id from fleets where owner_id = auth.uid()))
  with check (fleet_id in (select id from fleets where owner_id = auth.uid()));
