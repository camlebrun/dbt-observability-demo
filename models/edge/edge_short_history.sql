-- Trois jours seulement : historique insuffisant, le test doit ÉCHOUER.
select * from (select cast(ordered_at as date) as order_date, count(*) as n_orders from {{ ref('stg_orders') }} group by 1) where order_date in (
  select order_date from (select cast(ordered_at as date) as order_date, count(*) as n_orders from {{ ref('stg_orders') }} group by 1) order by order_date desc limit 3
)
