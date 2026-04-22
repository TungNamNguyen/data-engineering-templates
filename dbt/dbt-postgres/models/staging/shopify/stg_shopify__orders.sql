{#
    Staging — one-to-one with source('shopify', 'raw_orders').
    ✓ Rename, cast, derive is_completed   ✗ No joins or business logic
#}

with source as (
    select * from {{ source('shopify', 'raw_orders') }}
)

select
    id                      as order_id,
    customer_id,
    order_date::date        as order_date,
    status,
    (status = 'completed')  as is_completed
from source
