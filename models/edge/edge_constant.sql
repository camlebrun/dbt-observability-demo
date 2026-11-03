-- Activité parfaitement constante, aujourd'hui compris : écart type nul, le test doit PASSER.
select order_date, 100 as n_orders from (select cast(ordered_at as date) as order_date, count(*) as n_orders from {{ ref('stg_orders') }} group by 1)
