{{ config(materialized='table') }}
select cast(ordered_at as date) as order_date, count(*) as n_orders, sum(amount) as revenue
from {{ ref('stg_orders') }}
group by 1
