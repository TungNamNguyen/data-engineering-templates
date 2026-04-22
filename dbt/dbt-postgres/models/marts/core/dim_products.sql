{#
    Mart — product dimension with sales metrics.
    Grain: one row per product.
    Contract: enforced.
#}

with products as (
    select * from {{ ref('stg_shopify__products') }}
),

product_sales as (
    select
        product_id,
        sum(quantity)::integer        as total_units_sold,
        sum(line_total_usd)           as total_revenue_usd,
        count(distinct order_id)::integer as order_count
    from {{ ref('stg_shopify__order_items') }}
    group by product_id
)

select
    p.product_id,
    p.product_name,
    p.category,
    p.price_usd,
    p.is_active,
    p.created_at,
    coalesce(s.total_units_sold, 0)    as total_units_sold,
    coalesce(s.total_revenue_usd, 0)   as total_revenue_usd,
    coalesce(s.order_count, 0)         as order_count
from products p
left join product_sales s
    on p.product_id = s.product_id
