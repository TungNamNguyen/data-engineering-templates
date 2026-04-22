{#
    Mart — payment fact with order context.
    Grain: one row per payment transaction.
    Contract: enforced.
#}

with payments as (
    select * from {{ ref('stg_stripe__payments') }}
),

orders as (
    select order_id, customer_id, order_date
    from {{ ref('stg_shopify__orders') }}
)

select
    p.payment_id,
    p.order_id,
    o.customer_id,
    o.order_date,
    p.amount_usd,
    p.payment_method,
    p.status            as payment_status,
    (p.status = 'success') as is_successful,
    p.payment_date
from payments p
left join orders o
    on p.order_id = o.order_id
