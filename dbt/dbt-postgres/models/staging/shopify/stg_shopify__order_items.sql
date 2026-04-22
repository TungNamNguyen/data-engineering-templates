{#
    Staging — one-to-one with source('shopify', 'raw_order_items').
    ✓ Rename, derive USD amounts   ✗ No joins or business logic
#}

with source as (
    select * from {{ source('shopify', 'raw_order_items') }}
)

select
    id                                          as order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price_cents,
    {{ cents_to_dollars('unit_price_cents') }}   as unit_price_usd,
    quantity * {{ cents_to_dollars('unit_price_cents') }} as line_total_usd
from source
