with orders as (
    select * from {{ ref('silver_orders') }}
    where is_completed
)

select
    order_date,
    count(*)           as completed_orders,
    sum(amount_usd)    as revenue_usd
from orders
group by order_date
order by order_date
