{#
    Snapshot — tracks customer attribute changes using the CHECK strategy.

    SCD Type 2: the check strategy compares specific columns on every run.
    If any checked column changes, a new snapshot row is created.

    Use CHECK when the source table has no reliable `updated_at` column,
    or when you only care about specific columns changing.

    Run: cd dbt-postgres && DBT_PROFILES_DIR=.. uv run dbt snapshot
#}

{% snapshot scd_customers %}
{{
    config(
        target_schema='snapshots',
        unique_key='customer_id',
        strategy='check',
        check_cols=['email', 'country_code'],
    )
}}

select
    id              as customer_id,
    email,
    country_code
from {{ source('shopify', 'raw_customers') }}

{% endsnapshot %}
