-- Singular test: completed orders should always have positive revenue.
-- dbt considers a test failed when this query returns any rows.

select
    order_id,
    order_total_usd
from {{ ref('fct_orders') }}
where is_completed
  and order_total_usd <= 0
