create table if not exists service_places (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'garage',
  address text,
  phone text,
  memo text,
  created_at timestamptz not null default now()
);
alter table service_places enable row level security;
create policy "sp: anon read" on service_places for select using (true);
create policy "sp: anon insert" on service_places for insert with check (true);
create policy "sp: anon update" on service_places for update using (true) with check (true);
create policy "sp: anon delete" on service_places for delete using (true);
