{% macro parse_dbt_results_aggregates(upstream_ids, upstream_statuses) %}
    {#- A failed model reports status='error', a failed test reports
        status='fail' (or 'error' on a runtime error) -- both count as a
        failure here, since upstream nodes are commonly models. #}
    {% set upstream_count = upstream_ids | length %}
    {% set upstream_success_count = upstream_statuses | select('in', ['success', 'pass']) | list | length %}
    {% set upstream_fail_count = upstream_statuses | select('in', ['fail', 'error']) | list | length %}
    {% set upstream_unknown_count = upstream_statuses | select('equalto', 'unknown') | list | length %}
    {% set upstream_any_failure = upstream_fail_count > 0 %}
    {{ return({
        'upstream_count': upstream_count,
        'upstream_any_failure': upstream_any_failure,
        'upstream_success_count': upstream_success_count,
        'upstream_fail_count': upstream_fail_count,
        'upstream_unknown_count': upstream_unknown_count
    }) }}
{% endmacro %}
