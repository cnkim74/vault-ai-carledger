-- 테슬라 OAuth 토큰 보관 (단일 사용자 데모: id='default')
create table if not exists tesla_tokens (
  id text primary key default 'default',
  access_token text, refresh_token text, expires_at timestamptz,
  fleet_base text, vehicle_id text,
  updated_at timestamptz not null default now()
);
alter table tesla_tokens enable row level security;
-- 익명 정책 없음 → Edge Function(service_role)만 접근
