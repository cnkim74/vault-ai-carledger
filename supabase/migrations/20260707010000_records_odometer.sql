-- 정비 주기 계산용: 기록 시점 주행거리
alter table records add column if not exists odometer_km integer;
