-- Table entièrement vide : le test doit ÉCHOUER (pas d'historique).
select * from (select cast(ordered_at as date) as order_date, count(*) as n_orders from {{ ref('stg_orders') }} group by 1) where 1 = 0
