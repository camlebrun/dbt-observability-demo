-- Constante sauf aujourd'hui (101) : écart type nul, la moindre déviation doit ÉCHOUER.
select order_date, case when order_date = current_date then 101 else 100 end as n_orders
from (select cast(ordered_at as date) as order_date, count(*) as n_orders from {{ ref('stg_orders') }} group by 1)
