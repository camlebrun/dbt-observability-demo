{% macro parse_dbt_results(results) %}
    -- Create a list of parsed results
    {%- set parsed_results = [] %}
    -- Index this invocation's results by unique_id, for upstream lookups
    {% set results_by_id = parse_dbt_results_index(results) %}
    -- Flatten results and add to list
    {% for run_result in results %}
        -- Convert the run result object to a simple dictionary
        {% set run_result_dict = run_result.to_dict() %}
        -- Get the underlying dbt graph node that was executed
        {% set node = run_result_dict.get('node') %}
        {% set adapter_response = run_result_dict.get('adapter_response', {}) %}
        {% set rows_affected = adapter_response.get('rows_affected', 0) %}
        {%- if not rows_affected -%}
            {% set rows_affected = 0 %}
        {%- endif -%}
        {% set query_id = adapter_response.get('query_id') or adapter_response.get('job_id') %}

        -- Timing for the "execute" phase; absent for a skipped node.
        {% set timing = run_result_dict.get('timing', []) %}
        {% set execute_phase = (timing | selectattr('name', 'equalto', 'execute') | list | first) %}

        -- Best-effort scrape of dbt's own exception message shape:
        -- "... type=<X>, name=<Y> ...". Not a structured field dbt
        -- exposes -- empty on messages that don't contain those tokens
        -- (e.g. a plain test failure with no exception).
        {% set raw_message = run_result_dict.get('message', '') or '' %}
        {% set error_type = '' %}
        {% set error_name = '' %}
        {% if raw_message %}
            {% set type_start = raw_message.find('type=') %}
            {% if type_start != -1 %}
                {% set type_value = raw_message[type_start + 5:] %}
                {% set type_end = type_value.find(',') %}
                {% if type_end == -1 %}{% set type_end = type_value.find(')') %}{% endif %}
                {% if type_end != -1 %}{% set error_type = type_value[:type_end] %}{% endif %}
            {% endif %}
            {% set name_start = raw_message.find('name=') %}
            {% if name_start != -1 %}
                {% set name_value = raw_message[name_start + 5:] %}
                {% set name_end = name_value.find(',') %}
                {% if name_end == -1 %}{% set name_end = name_value.find(')') %}{% endif %}
                {% if name_end != -1 %}{% set error_name = name_value[:name_end] %}{% endif %}
            {% endif %}
        {% endif %}

        {% set db_name = node.get('database') %}
        {% set db_fqn_parts = [db_name, node.get('schema'), (node.get('alias') or node.get('name'))] %}

        -- Upstream dependencies' statuses, for root-cause attribution.
        {% set upstream_data = parse_dbt_results_upstream(node, results_by_id) %}
        {% set upstream_aggregates = parse_dbt_results_aggregates(upstream_data.ids, upstream_data.statuses) %}

        -- Lowercased for consistency: freshness check results
        -- (resource_type='source', logged through this same on-run-end
        -- hook -- dbt-fusion does fire it for `dbt source freshness`,
        -- unlike classic dbt-core) come back as "Pass"/"Warn"/"Error",
        -- capitalized, while model/test statuses are already lowercase.
        {% set status_value = (run_result_dict.get('status') or '') | lower %}

        {#- Real test name from the manifest, not a unique_id guess. -#}
        {% set test_generic_name = node.get('test_metadata', {}).get('name') if node.get('test_metadata') else none %}

        {#- Package owning the test macro, resolved from depends_on.macros
            (macro.<package>.test_<name>) -- generic, no per-test list.
            namespace() is required here, not a bare {% set %}: Jinja
            for-loops create a new scope per iteration, so a plain
            {% set test_package = ... %} inside the loop would never be
            visible after it ends. -#}
        {% set ns = namespace(test_package=none) %}
        {% if test_generic_name %}
            {% set expected_suffix = '.test_' ~ test_generic_name %}
            {% for macro_id in node.get('depends_on', {}).get('macros', []) %}
                {% if ns.test_package is none and macro_id.endswith(expected_suffix) %}
                    {% set ns.test_package = macro_id.split('.')[1] %}
                {% endif %}
            {% endfor %}
        {% endif %}

        {% set parsed_result_dict = {
                'result_id': invocation_id ~ '.' ~ node.get('unique_id'),
                'invocation_id': invocation_id,
                'unique_id': node.get('unique_id'),
                'started_at': execute_phase.get('started_at') if execute_phase else none,
                'completed_at': execute_phase.get('completed_at') if execute_phase else none,
                'resource_type': node.get('resource_type'),
                'materialization': node.get('config', {}).get('materialized'),
                'is_full_refresh': flags.FULL_REFRESH,
                'group_name': node.get('config', {}).get('group') or node.get('group'),
                'test_generic_name': test_generic_name,
                'test_package': ns.test_package,
                'test_column_name': node.get('column_name'),
                'db_system': target.type,
                'db_name': db_name,
                'db_schema': node.get('schema'),
                'db_sql_table': node.get('alias') or node.get('name'),
                'db_fqn': db_fqn_parts | join('.'),
                'status': status_value,
                'error_type': error_type,
                'error_name': error_name,
                'error_message': raw_message,
                'execution_time_seconds': run_result_dict.get('execution_time'),
                'rows_affected': rows_affected,
                'bytes_processed': adapter_response.get('bytes_processed'),
                'bytes_billed': adapter_response.get('bytes_billed'),
                'query_id': query_id,
                'upstream_ids': upstream_data.ids,
                'upstream_count': upstream_aggregates.upstream_count,
                'upstream_any_failure': upstream_aggregates.upstream_any_failure,
                'upstream_success_count': upstream_aggregates.upstream_success_count,
                'upstream_fail_count': upstream_aggregates.upstream_fail_count,
                'upstream_unknown_count': upstream_aggregates.upstream_unknown_count,
                'compiled_code': node.get('compiled_code'),
                }%}
        {% do parsed_results.append(parsed_result_dict) %}
    {% endfor %}
    {{ return(parsed_results) }}
{% endmacro %}
