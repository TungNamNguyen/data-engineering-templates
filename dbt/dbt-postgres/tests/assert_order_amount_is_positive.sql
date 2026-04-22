-- Singular test: every order must have a strictly positive amount.
-- dbt considers a test failed when this query returns any rows.

select
    order_id,
    amount_usd
from {{ ref('silver_orders') }}
where amount_usd <= 0
