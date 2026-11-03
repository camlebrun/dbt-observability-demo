{{ config(materialized = 'table') }}

with latest_test_runs as (
    select
        *,
        row_number() over (partition by unique_id order by started_at desc) as rn
    from {{ ref('dbt_results') }}
    where resource_type = 'test'
)

select
    unique_id,
    test_generic_name,
    test_package,
    test_column_name,
    db_fqn,
    status as latest_status,
    started_at as latest_run_at,
    test_package = 'dbt' as is_dbt_core
from latest_test_runs
where rn = 1
