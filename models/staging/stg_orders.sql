select order_id, customer_id, amount, ordered_at, _etl_loaded_at
from {{ source('shop', 'raw_orders') }}
