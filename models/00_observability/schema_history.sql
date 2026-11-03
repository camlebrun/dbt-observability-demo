{{
  config(
    materialized = 'incremental',
    transient = False,
    unique_key = 'result_id',
    on_schema_change = 'append_new_columns',
    alias = var('observability_schema_history_table'),
    pre_hook = "{% if is_incremental() %} delete from {{ this }} where valid_to is not null and valid_to < '{{ observability_retention_cutoff() }}' {% endif %}"
  )
}}

with empty_table as (
    select
        -- Key(s)
        cast(null as {{ dbt.type_string() }}) as result_id,
        cast(null as {{ dbt.type_string() }}) as unique_id,
        cast(null as {{ dbt.type_string() }}) as column_name,

        -- Temporal key(s) -- valid_to is null while the column is current
        cast(null as {{ dbt.type_string() }}) as valid_from,
        cast(null as {{ dbt.type_string() }}) as valid_to,

        -- Dimensional / descriptive attributes
        cast(null as {{ dbt.type_string() }}) as db_name,
        cast(null as {{ dbt.type_string() }}) as db_schema,
        cast(null as {{ dbt.type_string() }}) as db_sql_table,
        cast(null as {{ dbt.type_string() }}) as db_fqn,
        -- The live column's actual warehouse type (e.g. BigQuery's
        -- STRING/FLOAT64), not a documentation field.
        cast(null as {{ dbt.type_string() }}) as data_type,
        -- Only set when this row was closed because the column's type
        -- changed (not when the column was simply removed) -- the type
        -- it became, so you don't have to separately join to the row
        -- that replaced this one to see what it changed to.
        cast(null as {{ dbt.type_string() }}) as new_data_type,

        -- Status
        cast(null as {{ dbt.type_boolean() }}) as is_current,
        -- Only set when this row was closed -- explains why:
        -- 'type_changed' (column still exists, different data_type),
        -- 'column_dropped' (column no longer exists on a model that still
        -- ran), or 'model_deleted' (the model itself no longer exists in
        -- the project's manifest, regardless of this invocation's
        -- --select scope).
        cast(null as {{ dbt.type_string() }}) as close_reason,

        -- External ids -- which invocation opened/closed this row
        cast(null as {{ dbt.type_string() }}) as opened_invocation_id,
        cast(null as {{ dbt.type_string() }}) as closed_invocation_id
)

select * from empty_table
-- This is a filter so we will never actually insert these values
where 1 = 0
