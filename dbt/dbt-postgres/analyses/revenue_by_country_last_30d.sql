-- Analyses are ad-hoc SQL that dbt compiles but does NOT execute.
-- Use them for one-off investigations whose SQL you want version-controlled
-- alongside your models.
--
-- Compile with:   make compile
-- Then paste:     target/compiled/dbt_postgres/analyses/revenue_by_country_last_30d.sql
-- into your SQL client.

select
    c.country_name,
    count(*)             as order_count,
    sum(o.amount_usd)    as revenue_usd
from {{ ref('silver_orders') }}    as o
join {{ ref('silver_customers') }} as c using (customer_id)
where o.is_completed
  and o.order_date >= current_date - interval '30 days'
group by c.country_name
order by revenue_usd desc
