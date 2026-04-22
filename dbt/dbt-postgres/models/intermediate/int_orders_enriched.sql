{#
    Intermediate — enrich orders with line-item totals and payment summaries.

    Joins across two source systems:
      • Shopify: orders + order_items
      • Stripe:  payments

    ✓ Cross-source joins, aggregations
    ✗ Not exposed to end users / BI tools
#}

with orders as (
    select * from {{ ref('stg_shopify__orders') }}
),

order_items_agg as (
    select
        order_id,
        sum(line_total_usd)  as order_total_usd,
        count(*)             as item_count
    from {{ ref('stg_shopify__order_items') }}
    group by order_id
),

payments_agg as (
    select
        order_id,
        sum(case when status = 'success' then amount_usd else 0 end)
            as amount_paid_usd,
        count(case when status = 'success' then 1 end)
            as successful_payments
    from {{ ref('stg_stripe__payments') }}
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.status,
    o.is_completed,

    coalesce(oi.order_total_usd, 0)       as order_total_usd,
    coalesce(oi.item_count, 0)            as item_count,
    coalesce(p.amount_paid_usd, 0)        as amount_paid_usd,
    coalesce(p.successful_payments, 0)    as payment_count,

    coalesce(p.amount_paid_usd, 0)
        >= coalesce(oi.order_total_usd, 0)  as is_fully_paid

from orders o
left join order_items_agg oi on o.order_id = oi.order_id
left join payments_agg p     on o.order_id = p.order_id
