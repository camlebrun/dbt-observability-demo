{# Sévérité graduée : 1 ligne fautive = warn, plus de 5 = error. #}
{{ config(warn_if='>0', error_if='>5', meta={'expect': 'warn'}) }}
select order_id, amount from {{ ref('fct_orders') }} where amount < 0
