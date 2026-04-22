with orders as (
    select * from {{ ref('raw_orders') }}
)

select
    id                                  as order_id,
    customer_id,
    order_date,
    amount_cents,
    {{ cents_to_dollars('amount_cents') }} as amount_usd,
    status,
    status = 'completed'                as is_completed
from orders
