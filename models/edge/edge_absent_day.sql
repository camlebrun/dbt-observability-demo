-- Tout l'historique, sauf la date du jour : le test doit ÉCHOUER (panne totale du jour).
select * from (select cast(ordered_at as date) as order_date, count(*) as n_orders from {{ ref('stg_orders') }} group by 1) where order_date < current_date
