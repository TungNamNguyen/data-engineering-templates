{#
    Staging — one-to-one with source('shopify', 'raw_customers').
    ✓ Rename, cast, trim   ✗ No joins or business logic
#}

with source as (
    select * from {{ source('shopify', 'raw_customers') }}
)

select
    id                  as customer_id,
    first_name,
    last_name,
    lower(trim(email))  as email,
    upper(country_code) as country_code,
    created_at::date    as created_at
from source
