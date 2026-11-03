select customer_id, email, country
from {{ source('shop', 'raw_customers') }}
