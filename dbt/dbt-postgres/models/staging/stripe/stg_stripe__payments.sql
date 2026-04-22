{#
    Staging — one-to-one with source('stripe', 'raw_payments').
    ✓ Rename, cast, derive USD   ✗ No joins or business logic
#}

with source as (
    select * from {{ source('stripe', 'raw_payments') }}
)

select
    id                                        as payment_id,
    order_id,
    amount_cents,
    {{ cents_to_dollars('amount_cents') }}     as amount_usd,
    payment_method,
    status,
    created_at::date                          as payment_date
from source
