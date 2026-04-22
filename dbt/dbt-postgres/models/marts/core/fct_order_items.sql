{#
    Mart — order line-item fact with product and order context.
    Grain: one row per line item.
    Contract: enforced.
#}

with order_items as (
    select * from {{ ref('stg_shopify__order_items') }}
),

orders as (
    select order_id, customer_id, order_date
    from {{ ref('stg_shopify__orders') }}
),

products as (
    select product_id, product_name, category
    from {{ ref('stg_shopify__products') }}
)

select
    oi.order_item_id,
    oi.order_id,
    o.customer_id,
    o.order_date,
    oi.product_id,
    p.product_name,
    p.category,
    oi.quantity,
    oi.unit_price_usd,
    oi.line_total_usd
from order_items oi
left join orders o   on oi.order_id = o.order_id
left join products p on oi.product_id = p.product_id
