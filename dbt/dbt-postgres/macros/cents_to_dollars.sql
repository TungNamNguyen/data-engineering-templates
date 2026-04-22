{#
    Convert an integer-cents column to a numeric dollar amount.
    Example: {{ cents_to_dollars('amount_cents') }} → round(amount_cents / 100.0, 2)
#}

{% macro cents_to_dollars(column_name, precision=2) -%}
    round(cast(({{ column_name }} / 100.0) as numeric), {{ precision }})
{%- endmacro %}
