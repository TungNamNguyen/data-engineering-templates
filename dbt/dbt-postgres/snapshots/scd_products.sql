{#
    Snapshot — tracks product changes over time using the TIMESTAMP strategy.

    SCD Type 2: each change creates a new row with dbt_valid_from / dbt_valid_to.
    The timestamp strategy compares `updated_at` to detect changes automatically.

    Run: cd dbt-postgres && DBT_PROFILES_DIR=.. uv run dbt snapshot
#}

{% snapshot scd_products %}
{{
    config(
        target_schema='snapshots',
        unique_key='product_id',
        strategy='timestamp',
        updated_at='updated_at',
    )
}}

select
    id          as product_id,
    name        as product_name,
    category,
    price_cents,
    is_active,
    updated_at
from {{ source('shopify', 'raw_products') }}

{% endsnapshot %}
