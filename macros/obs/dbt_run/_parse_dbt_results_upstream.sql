{% macro parse_dbt_results_upstream(node, results_by_id) %}
    {#- Source dependencies are excluded, always -- a source never appears
        in `results` (dbt doesn't "run" a source), so counting it would
        always contribute an unknown status and drown out the real signal
        for models whose only upstream is a source. -#}
    {% set all_upstreams = node.get('depends_on', {}).get('nodes', []) %}
    {% set filtered = [] %}
    {% for up_id in all_upstreams %}
        {% if up_id[:7] != 'source.' %}{% do filtered.append(up_id) %}{% endif %}
    {% endfor %}
    {% set all_upstreams = filtered %}

    {% set upstream_statuses = [] %}
    {% for up_id in all_upstreams %}
        {% set up_result = results_by_id.get(up_id) %}
        {% if up_result %}
            {% set _ = upstream_statuses.append(up_result.to_dict().get('status', 'unknown')) %}
        {% else %}
            {% set _ = upstream_statuses.append('unknown') %}
        {% endif %}
    {% endfor %}
    {{ return({'ids': all_upstreams, 'statuses': upstream_statuses}) }}
{% endmacro %}
