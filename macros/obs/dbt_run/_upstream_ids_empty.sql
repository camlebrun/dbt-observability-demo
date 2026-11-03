{% macro upstream_ids_empty_cast() %}
    {#- "No upstreams" cast for `upstream_ids`, one branch per verified
        engine. No catch-all else branch -- an unverified engine should
        fail loudly, not guess wrong syntax. -#}
    {%- if target.type == 'bigquery' -%}
        CAST(NULL AS ARRAY<STRING>)
    {%- elif target.type == 'trino' -%}
        CAST(NULL AS ARRAY(VARCHAR(256)))
    {%- elif target.type == 'duckdb' -%}
        CAST(NULL AS VARCHAR[])
    {%- else -%}
        {{ exceptions.raise_compiler_error(
            "upstream_ids_empty_cast: no verified ARRAY-of-string cast for target.type='"
            ~ target.type ~ "'. Add a branch here once you've confirmed the correct syntax "
            ~ "(and nullability!) for this engine -- don't assume it matches another engine's."
        ) }}
    {%- endif -%}
{% endmacro %}

{% macro upstream_ids_array_literal(ids) %}
    {#- Non-empty array literal: ARRAY[...] works on BigQuery/Trino. -#}
    ARRAY[{% for id in ids %}{{ sql_literal(id) }}{% if not loop.last %}, {% endif %}{% endfor %}]
{% endmacro %}
