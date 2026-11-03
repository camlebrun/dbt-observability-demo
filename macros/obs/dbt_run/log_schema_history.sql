{% macro log_schema_history(results) %}
    {% set schema_history_relation = target.database ~ '.' ~ var('observability_dataset') ~ '.' ~ var('observability_schema_history_table') %}

    {% set now_iso = run_started_at.strftime('%Y-%m-%dT%H:%M:%S.%fZ') %}

    {#- Live materialized schema, not node.columns (only reflects the
        declared .yml, and only for documented/contract-enforced models). -#}
    {% set source_rows = [] %}
    {% set model_ids = [] %}
    {% for run_result in results %}
        {% set run_result_dict = run_result.to_dict() %}
        {% set node = run_result_dict.get('node') %}
        {#- 'success' and 'warn' both mean the model actually built and
            has a queryable relation; 'error'/'skipped' don't. -#}
        {#- Only track drift for this project's own models -- vendored
            package models (e.g. dbt_bigquery_monitoring) have schemas
            dictated by the package, not us, and including them blows the
            UNION ALL past BigQuery's 1MB query text limit. -#}
        {% if node and node.get('resource_type') == 'model' and node.get('package_name') == project_name and run_result_dict.get('status') in ('success', 'warn') %}
            {% set unique_id = node.get('unique_id') %}
            {% do model_ids.append(unique_id) %}
            {% set db_name = node.get('database') %}
            {% set db_schema = node.get('schema') %}
            {% set db_sql_table = node.get('alias') or node.get('name') %}
            {% set db_fqn = db_name ~ '.' ~ db_schema ~ '.' ~ db_sql_table %}
            {% set relation = api.Relation.create(database=db_name, schema=db_schema, identifier=db_sql_table) %}
            {% set live_columns = adapter.get_columns_in_relation(relation) %}
            {% for col in live_columns %}
                {% set source_row %}
                    select
                        {{ sql_literal(unique_id) }} as unique_id,
                        {{ sql_literal(col.name) }} as column_name,
                        {#- Normalized to a single casing so this project's
                            own comparisons stay consistent regardless of
                            what casing the adapter/dbt version happens to
                            return for the same live type. -#}
                        {{ sql_literal(col.dtype | upper) }} as data_type,
                        {{ sql_literal(db_name) }} as db_name,
                        {{ sql_literal(db_schema) }} as db_schema,
                        {{ sql_literal(db_sql_table) }} as db_sql_table,
                        {{ sql_literal(db_fqn) }} as db_fqn
                {% endset %}
                {% do source_rows.append(source_row) %}
            {% endfor %}
        {% endif %}
    {% endfor %}

    {#- Nothing built successfully this invocation -- nothing to diff via
        steps 1-3, but step 4 (deleted-model detection below) is
        independent of this invocation's own results, so it isn't gated
        by this. -#}
    {% if source_rows | length > 0 %}

    {% set source_sql %}
        {{ source_rows | join('\nunion all\n') }}
    {% endset %}

    {% set model_ids_sql %}
        {% for id in model_ids %}{{ sql_literal(id) }}{% if not loop.last %}, {% endif %}{% endfor %}
    {% endset %}

    {#- No UPDATE/MERGE: closing a row is INSERT-the-closed-copy (below) +
        DELETE-the-original (step 2), both plain filter/join SQL every
        engine supports, so there's no dialect gap to work around. -#}
    {% set insert_closed_copies_query %}
        insert into {{ schema_history_relation }} (
            result_id, unique_id, column_name, valid_from, valid_to,
            db_name, db_schema, db_sql_table, db_fqn, data_type,
            new_data_type, is_current, opened_invocation_id, closed_invocation_id,
            close_reason
        )
        select
            {{ dbt.concat([
                'old.unique_id', "'.'", 'old.column_name', "'.closed.'", sql_literal(now_iso)
            ]) }},
            old.unique_id,
            old.column_name,
            old.valid_from,
            {{ sql_literal(now_iso) }},
            old.db_name,
            old.db_schema,
            old.db_sql_table,
            old.db_fqn,
            old.data_type,
            new_state.data_type,
            false,
            old.opened_invocation_id,
            {{ sql_literal(invocation_id) }},
            -- A join match on (unique_id, column_name) with no data_type
            -- match (guaranteed by the WHERE below) means the column is
            -- still there under a different type; no match at all means
            -- it's gone.
            case when new_state.unique_id is not null then 'type_changed' else 'column_dropped' end
        from {{ schema_history_relation }} as old
        left join ({{ source_sql }}) as new_state
            on new_state.unique_id = old.unique_id
           and new_state.column_name = old.column_name
        where {{ schema_history_needs_closing(source_sql, model_ids_sql, prefix='old') }}
    {% endset %}
    {% do run_query(insert_closed_copies_query) %}

    {#- Step 2: delete the original open rows just superseded by their
        closed copies from step 1. Same filter as step 1, so nothing can
        be closed twice or left orphaned between them. -#}
    {% set delete_superseded_query %}
        delete from {{ schema_history_relation }} as del
        where {{ schema_history_needs_closing(source_sql, model_ids_sql, prefix='del') }}
    {% endset %}
    {% do run_query(delete_superseded_query) %}

    {#- Step 3: open a fresh row for anything that doesn't already have a
        currently-open row matching its (unique_id, column_name,
        data_type) -- covers genuinely new columns, and columns whose
        data_type just changed (closed above, so this now finds no open
        match and opens a new one). Unchanged columns already have a
        matching open row, so NOT EXISTS is false for them -- no-op, no
        duplicate row. -#}
    {% set open_query %}
        insert into {{ schema_history_relation }} (
            result_id, unique_id, column_name, valid_from, valid_to,
            db_name, db_schema, db_sql_table, db_fqn, data_type,
            new_data_type, is_current, opened_invocation_id, closed_invocation_id,
            close_reason
        )
        select
            {{ dbt.concat([
                'src.unique_id', "'.'", 'src.column_name', "'.'", sql_literal(now_iso)
            ]) }},
            src.unique_id,
            src.column_name,
            {{ sql_literal(now_iso) }},
            cast(null as {{ dbt.type_string() }}),
            src.db_name,
            src.db_schema,
            src.db_sql_table,
            src.db_fqn,
            src.data_type,
            cast(null as {{ dbt.type_string() }}),
            true,
            {{ sql_literal(invocation_id) }},
            cast(null as {{ dbt.type_string() }}),
            cast(null as {{ dbt.type_string() }})
        from (
            {{ source_sql }}
        ) as src
        where not exists (
            select 1
            from {{ schema_history_relation }} as existing
            where existing.unique_id = src.unique_id
              and existing.column_name = src.column_name
              -- Case-insensitive, matching _schema_history_needs_closing --
              -- see the comment there.
              and upper(coalesce(existing.data_type, '')) = upper(coalesce(src.data_type, ''))
              and existing.valid_to is null
        )
    {% endset %}
    {% do run_query(open_query) %}

    {% endif %}

    {#- Step 4: close rows for models that no longer exist anywhere in the
        project (deleted, renamed) -- `graph` is dbt's full parsed
        manifest, unaffected by this invocation's --select/--exclude, so
        this is safe to run every invocation regardless of how narrow the
        selection was (we run per db/model in normal usage, never a full
        project run). -#}
    {#- `graph` is a plain dict, not an object -- during `dbt parse` (which
        compiles on-run-end operations to validate them, before any
        manifest/graph is built) it's `{}`, so `graph.nodes` raises
        "'dict object' has no attribute 'nodes'". `.get('nodes', {})`
        degrades to an empty loop instead of failing compilation. -#}
    {% set all_project_model_ids = [] %}
    {% for uid, node in graph.get('nodes', {}).items() %}
        {% if node.get('resource_type') == 'model' and node.get('package_name') == project_name %}
            {% do all_project_model_ids.append(uid) %}
        {% endif %}
    {% endfor %}

    {% if all_project_model_ids | length > 0 %}
        {% set all_project_model_ids_sql %}
            {% for uid in all_project_model_ids %}{{ sql_literal(uid) }}{% if not loop.last %}, {% endif %}{% endfor %}
        {% endset %}

        {% set insert_deleted_model_copies_query %}
            insert into {{ schema_history_relation }} (
                result_id, unique_id, column_name, valid_from, valid_to,
                db_name, db_schema, db_sql_table, db_fqn, data_type,
                new_data_type, is_current, opened_invocation_id, closed_invocation_id,
                close_reason
            )
            select
                {{ dbt.concat([
                    'old.unique_id', "'.'", 'old.column_name', "'.closed.'", sql_literal(now_iso)
                ]) }},
                old.unique_id,
                old.column_name,
                old.valid_from,
                {{ sql_literal(now_iso) }},
                old.db_name,
                old.db_schema,
                old.db_sql_table,
                old.db_fqn,
                old.data_type,
                cast(null as {{ dbt.type_string() }}),
                false,
                old.opened_invocation_id,
                {{ sql_literal(invocation_id) }},
                'model_deleted'
            from {{ schema_history_relation }} as old
            where old.valid_to is null
              and old.unique_id not in ({{ all_project_model_ids_sql }})
        {% endset %}
        {% do run_query(insert_deleted_model_copies_query) %}

        {% set delete_superseded_deleted_models_query %}
            delete from {{ schema_history_relation }}
            where valid_to is null
              and unique_id not in ({{ all_project_model_ids_sql }})
        {% endset %}
        {% do run_query(delete_superseded_deleted_models_query) %}
    {% endif %}

    {{ return('') }}
{% endmacro %}
