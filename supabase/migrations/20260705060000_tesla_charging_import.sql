-- 외부 소스(테슬라 슈퍼차저 등) 중복 방지용 식별자
alter table records add column if not exists ext_id text;
create unique index if not exists records_vehicle_ext_id_uidx
  on records (vehicle_id, ext_id) where ext_id is not null;

-- 테슬라 충전 이력 조회에 필요한 VIN 저장
alter table tesla_tokens add column if not exists vin text;
