{#
    Intermediate — per-customer order aggregation.

    Provides lifetime metrics consumed by dim_customers and other marts.
    Built on top of int_orders_enriched so payment data is already included.
#}

with enriched_orders as (
    select * from {{ ref('int_orders_enriched') }}
)

select
    customer_id,
    count(*)                                          as order_count,
    count(case when is_completed then 1 end)          as completed_order_count,
    sum(order_total_usd)                              as lifetime_spend_usd,
    sum(amount_paid_usd)                              as lifetime_paid_usd,
    min(order_date)                                   as first_order_date,
    max(order_date)                                   as last_order_date
from enriched_orders
group by customer_id
