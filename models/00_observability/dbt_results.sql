{{
  config(
    materialized = 'incremental',
    transient = False,
    unique_key = 'result_id',
    on_schema_change = 'append_new_columns',
    alias = var('observability_dbt_results_table'),
    pre_hook = "{% if is_incremental() %} delete from {{ this }} where coalesce(completed_at, started_at) < '{{ observability_retention_cutoff() }}' {% endif %}"
  )
}}

with empty_table as (
    select
        -- Key(s)
        cast(null as {{ dbt.type_string() }}) as result_id,
        cast(null as {{ dbt.type_string() }}) as invocation_id,
        cast(null as {{ dbt.type_string() }}) as unique_id,

        -- Temporal key(s) -- the "execute" phase of run_result.timing;
        -- NULL for a skipped node (no "execute" phase)
        cast(null as {{ dbt.type_string() }}) as started_at,
        cast(null as {{ dbt.type_string() }}) as completed_at,

        -- Dimensional / descriptive attributes
        cast(null as {{ dbt.type_string() }}) as resource_type,
        cast(null as {{ dbt.type_string() }}) as materialization,
        -- flags.FULL_REFRESH for the whole invocation, not per-node --
        -- lets a big rows_affected/bytes_billed spike be attributed to a
        -- --full-refresh instead of misread as incremental drift.
        cast(null as {{ dbt.type_boolean() }}) as is_full_refresh,
        -- dbt's `group` config (node.group in the manifest); NULL for
        -- ungrouped nodes -- most resource types don't have one. Named
        -- group_name, not group, since GROUP is a SQL keyword.
        cast(null as {{ dbt.type_string() }}) as group_name,
        -- Generic test name (dbt/dbt_utils/custom), from test_metadata.
        cast(null as {{ dbt.type_string() }}) as test_generic_name,
        -- Package defining the test macro (dbt, dbt_utils, or this
        -- project), from depends_on.macros.
        cast(null as {{ dbt.type_string() }}) as test_package,
        -- The specific column a test targets (node.column_name); more
        -- reliable than parsing it out of db_fqn/unique_id.
        cast(null as {{ dbt.type_string() }}) as test_column_name,
        cast(null as {{ dbt.type_string() }}) as db_system,
        cast(null as {{ dbt.type_string() }}) as db_name,
        cast(null as {{ dbt.type_string() }}) as db_schema,
        cast(null as {{ dbt.type_string() }}) as db_sql_table,
        cast(null as {{ dbt.type_string() }}) as db_fqn,

        -- Status
        cast(null as {{ dbt.type_string() }}) as status,
        -- Best-effort scrape of run_result.message's `type=`/`name=`
        -- tokens (dbt's own exception message shape) -- not a structured
        -- field dbt exposes, so empty on messages that don't contain them
        -- (e.g. a plain test failure).
        cast(null as {{ dbt.type_string() }}) as error_type,
        cast(null as {{ dbt.type_string() }}) as error_name,
        cast(null as {{ dbt.type_string() }}) as error_message,

        -- Metrics / measures
        cast(null as {{ dbt.type_float() }}) as execution_time_seconds,
        cast(null as {{ dbt.type_int() }}) as rows_affected,
        -- BigQuery-only (BigQueryAdapterResponse); always NULL on Trino
        -- (TrinoAdapterResponse has no bytes_* fields at all) and DuckDB
        -- (doesn't extend AdapterResponse beyond the base dbt-core class).
        cast(null as {{ dbt.type_int() }}) as bytes_processed,
        cast(null as {{ dbt.type_int() }}) as bytes_billed,

        -- External system id
        cast(null as {{ dbt.type_string() }}) as query_id,

        -- Upstream aggregates -- did this node's dependencies succeed?
        -- Source dependencies are excluded (they never appear in `results`,
        -- so they'd always show as unknown and drown out the real signal).
        {{ upstream_ids_empty_cast() }} as upstream_ids,
        cast(null as {{ dbt.type_int() }}) as upstream_count,
        cast(null as {{ dbt.type_boolean() }}) as upstream_any_failure,
        cast(null as {{ dbt.type_int() }}) as upstream_success_count,
        cast(null as {{ dbt.type_int() }}) as upstream_fail_count,
        cast(null as {{ dbt.type_int() }}) as upstream_unknown_count,

        -- Large payload, last
        cast(null as {{ dbt.type_string() }}) as compiled_code
)

select * from empty_table
-- This is a filter so we will never actually insert these values
where 1 = 0
