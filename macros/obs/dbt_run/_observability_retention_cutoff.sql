{% macro observability_retention_cutoff() %}
    {#- ISO cutoff string, formatted like started_at/completed_at/valid_to
        are actually stored, so a plain VARCHAR `<` works on every engine
        with no per-adapter date function needed. -#}
    {%- set retention_days = var('observability_retention_days') -%}
    {%- set cutoff = run_started_at - modules.datetime.timedelta(days=retention_days) -%}
    {{ return(cutoff.strftime('%Y-%m-%dT%H:%M:%S.%fZ')) }}
{% endmacro %}
