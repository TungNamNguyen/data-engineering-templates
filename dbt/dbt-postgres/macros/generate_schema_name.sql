{#
    Override dbt's default schema resolution.

    Default behavior: custom +schema values are concatenated onto target.schema
    (e.g. schema `analytics` + `+schema: staging` → `analytics_staging`). That's
    a pain when you want literal layer schemas like `staging`, `intermediate`,
    `marts`. This macro uses the custom value verbatim when set, and falls
    back to target.schema otherwise.

    Schema mapping (dbt_project.yml):
      staging      → schema `staging`
      intermediate → schema `intermediate`
      marts        → schema `marts`
      seeds/raw    → schema `raw`
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
