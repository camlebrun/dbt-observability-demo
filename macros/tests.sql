{% test null_rate_below(model, column_name, max_rate) %}
select null_rate
from (
  select countif({{ column_name }} is null) * 1.0 / count(*) as null_rate
  from {{ model }}
)
where null_rate > {{ max_rate }}
{% endtest %}

{#
  Volume : compare la valeur de la date attendue à la moyenne et à l'écart type des jours précédents.
  - une date absente compte comme 0 (une panne totale n'est plus invisible) ;
  - un historique trop court ou vide échoue (on ne juge pas sans référence) ;
  - un écart type nul est géré : toute déviation échoue, une valeur identique passe.
  Attention : `current_date` suit le fuseau du moteur (UTC sur BigQuery).
#}
{% test volume_anomaly(model, date_column, value_column, max_sigma=3, expected_date='current_date', min_history=7) %}
with ref as (
  select count(*) as n_ref, avg({{ value_column }}) as moy, stddev_samp({{ value_column }}) as ecart
  from {{ model }} where {{ date_column }} < {{ expected_date }}
),
attendu as (
  select coalesce(sum({{ value_column }}), 0) as valeur
  from {{ model }} where {{ date_column }} = {{ expected_date }}
)
select attendu.valeur, ref.n_ref, ref.moy, ref.ecart
from attendu, ref
where ref.n_ref < {{ min_history }}
   or abs(attendu.valeur - ref.moy) > {{ max_sigma }} * coalesce(ref.ecart, 0)
{% endtest %}

{# Bornes métier : toute valeur hors de [min_value, max_value] échoue (valeurs valides mais absurdes). #}
{% test values_between(model, column_name, min_value, max_value) %}
select {{ column_name }} from {{ model }}
where {{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }}
{% endtest %}

{# Aucun horodatage dans le futur : un chargement « de demain » rend la fraîcheur muette. #}
{% test no_future_timestamps(model, column_name) %}
select {{ column_name }} from {{ model }} where {{ column_name }} > current_timestamp
{% endtest %}

{# Surveille l'amont : les colonnes de la relation doivent être exactement celles attendues. #}
{% test columns_match(model, expected) %}
{% set missing = [] %}{% set extra = [] %}
{% if execute %}
  {% set actual = adapter.get_columns_in_relation(model) | map(attribute='name') | map('lower') | list %}
  {% set wanted = expected | map('lower') | list %}
  {% for c in wanted if c not in actual %}{% do missing.append(c) %}{% endfor %}
  {% for c in actual if c not in wanted %}{% do extra.append(c) %}{% endfor %}
{% endif %}
select colonnes_en_ecart from (select '{{ (missing + extra) | join(",") }}' as colonnes_en_ecart, {{ missing | length + extra | length }} as n) where n > 0
{% endtest %}
