{% macro schema_history_needs_closing(source_sql, model_ids_sql, prefix) %}
    {#- An open row (for a model in this invocation) with no surviving
        source match on (unique_id, column_name, data_type) -- either the
        column disappeared, or its data_type changed.

        `prefix` is REQUIRED, even for a plain DELETE with no join --
        never call this with bare/unqualified columns. On BigQuery, an
        unqualified column inside this correlated NOT EXISTS subquery
        resolves to the subquery's own `src` alias (innermost scope),
        not the outer table, silently turning `src.x = x` into a
        tautology `src.x = src.x`. That makes NOT EXISTS always false
        and the DELETE a permanent no-op with no error -- exactly what
        happened here before this was caught by an end-to-end test:
        closed rows were inserted correctly but the original open row
        was never actually deleted, leaving duplicate/overlapping rows
        for every single close event. Callers must alias the target
        relation (a short alias like `t`, not its multi-part name --
        that doesn't parse on BigQuery) and pass that alias as `prefix`. -#}
    {% set p = prefix ~ '.' %}
    {{ p }}valid_to is null
    and {{ p }}unique_id in ({{ model_ids_sql }})
    {#- Case-insensitive on data_type: the same live type can come back
        with different casing across dbt/adapter versions (e.g. BigQuery
        'STRING' vs 'string'), and a bare = would treat that as a real
        type change, closing+reopening a row that never actually
        changed. -#}
    and not exists (
        select 1
        from ({{ source_sql }}) as src
        where src.unique_id = {{ p }}unique_id
          and src.column_name = {{ p }}column_name
          and upper(coalesce(src.data_type, '')) = upper(coalesce({{ p }}data_type, ''))
    )
{% endmacro %}
