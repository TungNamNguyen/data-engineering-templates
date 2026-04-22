{#
    Override dbt's default schema resolution.

    Default behavior: custom +schema values are concatenated onto target.schema
    (e.g. schema `analytics` + `+schema: silver` → `analytics_silver`). That's
    a pain when you want literal medallion schemas like `bronze`, `silver`,
    `gold`. This macro uses the custom value verbatim when set, and falls
    back to target.schema otherwise.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
