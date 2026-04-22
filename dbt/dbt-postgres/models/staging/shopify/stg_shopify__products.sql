{#
    Staging — one-to-one with source('shopify', 'raw_products').
    ✓ Rename, cast, derive USD price   ✗ No joins or business logic
#}

with source as (
    select * from {{ source('shopify', 'raw_products') }}
)

select
    id                                        as product_id,
    name                                      as product_name,
    category,
    price_cents,
    {{ cents_to_dollars('price_cents') }}      as price_usd,
    is_active,
    created_at::date                          as created_at,
    updated_at
from source
