with customers as (
    select * from {{ ref('raw_customers') }}
),

countries as (
    select * from {{ ref('country_codes') }}
)

select
    c.id                             as customer_id,
    c.first_name,
    c.last_name,
    c.first_name || ' ' || c.last_name as full_name,
    lower(c.email)                   as email,
    c.country_code,
    coalesce(co.name, 'Unknown')     as country_name,
    c.signup_date
from customers c
left join countries co
    on c.country_code = co.code
