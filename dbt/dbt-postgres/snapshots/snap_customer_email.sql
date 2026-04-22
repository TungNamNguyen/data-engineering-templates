{#
    Example snapshot — tracks changes to a customer's email over time using
    the `check` strategy. Commented out by default because snapshots must
    persist across runs (they write to their own schema and rely on existing
    rows); uncomment when you have a real source of truth to snapshot.

    Run with: make PROJECT=dbt-postgres seed && uv run --project dbt-postgres \
             dbt snapshot   # or: cd dbt-postgres && uv run dbt snapshot
#}

-- {% snapshot snap_customer_email %}
-- {{
--     config(
--       target_schema='snapshots',
--       unique_key='id',
--       strategy='check',
--       check_cols=['email'],
--     )
-- }}
-- select id, email
-- from {{ ref('raw_customers') }}
-- {% endsnapshot %}
