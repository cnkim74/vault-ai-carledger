-- 차종 카테고리 (car / motorcycle / scooter)
alter table vehicles add column if not exists category text not null default 'car';
