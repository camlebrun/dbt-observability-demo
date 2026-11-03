{% macro log_dbt_results(results) %}
    {% set parsed_results = parse_dbt_results(results) %}
    {% if parsed_results | length == 0 %}
        {{ return('') }}
    {% endif %}

    {% set relation = target.database ~ '.' ~ var('observability_dataset') ~ '.' ~ var('observability_dbt_results_table') %}

    {% set insert_columns = [
        'result_id', 'invocation_id', 'unique_id', 'started_at', 'completed_at',
        'resource_type', 'materialization', 'is_full_refresh', 'group_name', 'test_generic_name',
        'test_package', 'test_column_name', 'db_system', 'db_name',
        'db_schema', 'db_sql_table', 'db_fqn', 'status', 'error_type', 'error_name',
        'error_message', 'execution_time_seconds', 'rows_affected',
        'bytes_processed', 'bytes_billed', 'query_id', 'upstream_ids',
        'upstream_count', 'upstream_any_failure', 'upstream_success_count',
        'upstream_fail_count', 'upstream_unknown_count', 'compiled_code'
    ] %}

    {% set value_rows = [] %}
    {% for result in parsed_results %}
        {% if result.upstream_ids | length > 0 %}
            {% set upstream_ids_sql = upstream_ids_array_literal(result.upstream_ids) %}
        {% else %}
            {% set upstream_ids_sql = upstream_ids_empty_cast() %}
        {% endif %}

        {% set any_failure_sql %}{{ result.upstream_any_failure | upper }}{% endset %}

        {% set column_values = {
            'result_id': "'" ~ result.result_id ~ "'",
            'invocation_id': "'" ~ result.invocation_id ~ "'",
            'unique_id': "'" ~ result.unique_id ~ "'",
            'started_at': sql_literal(result.started_at),
            'completed_at': sql_literal(result.completed_at),
            'resource_type': "'" ~ result.resource_type ~ "'",
            'materialization': sql_literal(result.materialization),
            'is_full_refresh': sql_literal(result.is_full_refresh),
            'group_name': sql_literal(result.group_name),
            'test_generic_name': sql_literal(result.test_generic_name),
            'test_package': sql_literal(result.test_package),
            'test_column_name': sql_literal(result.test_column_name),
            'db_system': "'" ~ target.type ~ "'",
            'db_name': sql_literal(result.db_name),
            'db_schema': "'" ~ result.db_schema ~ "'",
            'db_sql_table': "'" ~ result.db_sql_table ~ "'",
            'db_fqn': "'" ~ result.db_fqn ~ "'",
            'status': "'" ~ result.status ~ "'",
            'error_type': sql_literal(result.error_type),
            'error_name': sql_literal(result.error_name),
            'error_message': sql_literal(result.error_message),
            'execution_time_seconds': result.execution_time_seconds,
            'rows_affected': result.rows_affected,
            'bytes_processed': sql_literal(result.bytes_processed),
            'bytes_billed': sql_literal(result.bytes_billed),
            'query_id': sql_literal(result.query_id),
            'upstream_ids': upstream_ids_sql,
            'upstream_count': result.upstream_count,
            'upstream_any_failure': any_failure_sql,
            'upstream_success_count': result.upstream_success_count,
            'upstream_fail_count': result.upstream_fail_count,
            'upstream_unknown_count': result.upstream_unknown_count,
            'compiled_code': sql_literal(result.compiled_code)
        } %}

        {% set row_values = [] %}
        {% for col in insert_columns %}
            {% do row_values.append(column_values[col]) %}
        {% endfor %}
        {% set row_sql = '(' ~ (row_values | join(', ')) ~ ')' %}
        {% do value_rows.append(row_sql) %}
    {% endfor %}

    {#- Named columns, not positional: on_schema_change=append_new_columns
        always ALTER TABLE ADD COLUMN at the end of the physical table on
        BigQuery, regardless of this list's order, so a bare `values (...)`
        insert would misalign as soon as they diverge. -#}
    {% set insert_query %}
        insert into {{ relation }} (
            {{ insert_columns | join(', ') }}
        )
        values {{ value_rows | join(',\n') }}
    {% endset %}
    {% do run_query(insert_query) %}
    {{ return('') }}
{% endmacro %}
