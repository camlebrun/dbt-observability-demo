{#- Renders a Python value as a SQL literal (NULL-safe) for use inside
    hand-built INSERT statements. Dispatches on the Jinja value's type:
    - none -> NULL
    - boolean -> bare TRUE/FALSE (valid on BigQuery, DuckDB, and Trino alike)
    - number -> bare numeric literal
    - anything else -> quoted string literal via dbt's adapter-dispatched
      cross-database macros (https://docs.getdbt.com/reference/dbt-jinja-functions/cross-database-macros),
      which already handle BigQuery vs. ANSI quote/newline escaping.

    Why numbers/booleans must stay bare (not quoted) -- verified against a
    live Trino 482 container, not just docs:
        insert into t (n integer) values ('42')   -> fails: "Insert query
            has mismatched column types: Table: [integer], Query: [varchar(2)]"
        insert into t (b boolean) values ('true') -> same mismatch error
    Trino (like BigQuery, per its docs: "String literals don't coerce to
    numeric types") does NOT implicitly coerce a quoted string into a
    numeric/boolean column on INSERT. DuckDB is the permissive outlier and
    tolerates the quoted form, so bare rendering is required for portability,
    not optional.

    Why default__escape_single_quotes (doubled '' ) is correct for Trino:

    verified on the same container that dbt's ANSI-default escaping round-trips
    correctly, e.g. escape_single_quotes("they're ain't a word") ->
    "they''re ain''t a word", inserted and read back as "they're ain't a word".

    BigQuery also treats backslash as an escape character inside string
    literals (unlike DuckDB/Trino's ANSI-default literals), so a value
    containing a literal backslash not already valid as a BigQuery escape
    (e.g. compiled_code containing "\." from a regex) raises "Illegal escape
    sequence" once inlined. Backslashes must be doubled before quoting, and
    only for BigQuery -- doubling them for DuckDB/Trino would corrupt the
    round-trip since those dialects don't unescape backslashes at all. -#}
{% macro sql_literal(value) %}
    {%- if value is none -%}
        NULL
    {%- elif value is boolean -%}
        {{ value | upper }}
    {%- elif value is number -%}
        {{ value }}
    {%- else -%}
        {%- set string_value = value | string -%}
        {%- if target.type == 'bigquery' -%}
            {%- set string_value = string_value | replace('\\', '\\\\') -%}
        {%- endif -%}
        {{ dbt.string_literal(dbt.escape_single_quotes(string_value)) }}
    {%- endif -%}
{% endmacro %}
