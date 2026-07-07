create table if not exists conversations (
  id uuid primary key default gen_random_uuid(),
  title text not null default '대화',
  messages jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table conversations enable row level security;
create policy "conv: anon read" on conversations for select using (true);
create policy "conv: anon insert" on conversations for insert with check (true);
create policy "conv: anon update" on conversations for update using (true) with check (true);
create policy "conv: anon delete" on conversations for delete using (true);
