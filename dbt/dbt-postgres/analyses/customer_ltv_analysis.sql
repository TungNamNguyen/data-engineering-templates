-- Customer lifetime value analysis.
-- Compile with: make compile
-- Then paste:   target/compiled/dbt_postgres/analyses/customer_ltv_analysis.sql

select
    c.customer_id,
    c.full_name,
    c.country_name,
    c.order_count,
    c.lifetime_spend_usd,
    c.lifetime_paid_usd,
    c.first_order_date,
    c.last_order_date,
    case
        when c.lifetime_spend_usd >= 500 then 'high'
        when c.lifetime_spend_usd >= 100 then 'medium'
        else 'low'
    end as ltv_tier
from {{ ref('dim_customers') }} c
where c.order_count > 0
order by c.lifetime_spend_usd desc
