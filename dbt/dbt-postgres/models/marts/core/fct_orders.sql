{#
    Mart — order fact with customer and payment context.
    Grain: one row per order.
    Contract: enforced.
#}

with enriched as (
    select * from {{ ref('int_orders_enriched') }}
),

customers as (
    select
        customer_id,
        first_name || ' ' || last_name  as customer_name,
        country_code
    from {{ ref('stg_shopify__customers') }}
)

select
    e.order_id,
    e.customer_id,
    c.customer_name,
    c.country_code,
    e.order_date,
    e.status            as order_status,
    e.is_completed,
    e.item_count,
    e.order_total_usd,
    e.amount_paid_usd,
    e.payment_count,
    e.is_fully_paid
from enriched e
left join customers c
    on e.customer_id = c.customer_id
