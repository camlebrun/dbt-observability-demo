{% macro parse_dbt_results_index(results) %}
    {#- Builds a unique_id -> run_result lookup for this invocation, so
        each node's upstream dependencies can be resolved by status
        without an O(n) scan per node. -#}
    {% set results_by_id = {} %}
    {% for run_result in results %}
        {% set rid = run_result.to_dict().get('node', {}).get('unique_id', '') %}
        {% if rid %}
            {% set _ = results_by_id.update({rid: run_result}) %}
        {% endif %}
    {% endfor %}
    {{ return(results_by_id) }}
{% endmacro %}
