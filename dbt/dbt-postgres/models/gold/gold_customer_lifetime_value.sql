with customers as (
    select * from {{ ref('silver_customers') }}
),

orders as (
    select *
    from {{ ref('silver_orders') }}
    where is_completed
),

customer_orders as (
    select
        customer_id,
        count(*)           as order_count,
        sum(amount_usd)    as lifetime_value_usd,
        min(order_date)    as first_order_date,
        max(order_date)    as last_order_date
    from orders
    group by customer_id
)

select
    c.customer_id,
    c.full_name,
    c.country_name,
    c.signup_date,
    coalesce(co.order_count, 0)        as order_count,
    coalesce(co.lifetime_value_usd, 0) as lifetime_value_usd,
    co.first_order_date,
    co.last_order_date
from customers c
left join customer_orders co using (customer_id)
