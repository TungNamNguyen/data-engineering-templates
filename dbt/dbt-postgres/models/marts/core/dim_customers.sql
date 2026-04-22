{#
    Mart — customer dimension with lifetime order metrics.
    Grain: one row per customer.
    Contract: enforced.
#}

with customers as (
    select * from {{ ref('stg_shopify__customers') }}
),

countries as (
    select * from {{ ref('seed_country_codes') }}
),

customer_orders as (
    select * from {{ ref('int_customer_orders') }}
)

select
    c.customer_id,
    c.first_name,
    c.last_name,
    c.first_name || ' ' || c.last_name   as full_name,
    c.email,
    c.country_code,
    coalesce(co.country_name, 'Unknown')  as country_name,
    c.created_at,
    coalesce(o.order_count, 0)            as order_count,
    coalesce(o.completed_order_count, 0)  as completed_order_count,
    coalesce(o.lifetime_spend_usd, 0)     as lifetime_spend_usd,
    coalesce(o.lifetime_paid_usd, 0)      as lifetime_paid_usd,
    o.first_order_date,
    o.last_order_date
from customers c
left join countries co
    on c.country_code = co.country_code
left join customer_orders o
    on c.customer_id = o.customer_id
