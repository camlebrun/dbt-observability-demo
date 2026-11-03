{{ config(materialized='incremental', unique_key='order_id', on_schema_change='append_new_columns') }}
select distinct order_id, customer_id, amount, ordered_at from {{ ref('stg_orders') }}
