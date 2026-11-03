"""Matrice de mutations : quels contrôles détectent quelle altération ?

Pour chaque mutation : données saines -> seed -> altération SQL -> dbt build -> dbt source freshness.
On relève ce qui n'est plus « pass ». Une altération que personne ne voit est un trou dans la couverture.

Usage : DBT=dbt python scripts/mutate.py   (nécessite le module Python `duckdb`)
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import duckdb

DBT = os.environ.get("DBT", "dbt")
ENV = {**os.environ, "DBT_PROFILES_DIR": "."}
TODAY = "cast(ordered_at as date) = current_date"

MUTATIONS = [
    ("Aucune altération (référence)", None),
    ("Jour entièrement absent", f"delete from raw_orders where {TODAY}"),
    ("Volume du jour divisé par deux", f"delete from raw_orders where {TODAY} and order_id % 2 = 0"),
    ("Volume du jour doublé (nouveaux identifiants)", f"insert into raw_orders select order_id + 100000, customer_id, amount, ordered_at, _etl_loaded_at from raw_orders where {TODAY}"),
    ("Une commande en double", "insert into raw_orders select * from raw_orders where order_id = (select min(order_id) from raw_orders)"),
    ("Client manquant (NULL) sur 2 % des lignes", "update raw_orders set customer_id = null where order_id % 50 = 0"),
    ("Client inconnu (999) sur 2 % des lignes", "update raw_orders set customer_id = 999 where order_id % 50 = 0"),
    ("Montant négatif sur 0,5 % des lignes", "update raw_orders set amount = -amount where order_id % 200 = 0"),
    ("Montant manquant (NULL) sur 10 % des lignes", "update raw_orders set amount = null where order_id % 10 = 0"),
    ("Montants multipliés par 100 (valeurs valides mais fausses)", "update raw_orders set amount = amount * 100"),
    ("Clients permutés (clés valides mais fausses)", "update raw_orders set customer_id = 1 + (customer_id % 40)"),
    ("Toutes les dates décalées d'un jour", "update raw_orders set ordered_at = ordered_at + interval 1 day"),
    ("Dernier chargement vieux de 30 h", "update raw_orders set _etl_loaded_at = _etl_loaded_at - interval 30 hour"),
    ("Dernier chargement une heure dans le futur", "update raw_orders set _etl_loaded_at = _etl_loaded_at + ((now() + interval 1 hour) - (select max(_etl_loaded_at) from raw_orders))"),   # une heure réelle d'avance, quel que soit le fuseau
    ("Colonne ajoutée en amont", "alter table raw_orders add column promo_code varchar"),
    ("Type de colonne modifié en amont (amount -> texte)", "alter table raw_orders alter amount type varchar"),
    ("Colonne renommée en amont (amount -> montant)", "alter table raw_orders rename column amount to montant"),
]


def run(*args):
    return subprocess.run([DBT, *args], env=ENV, capture_output=True, text=True)


def short(uid):
    """Nom lisible d'un test à partir de son identifiant dbt."""
    parts = uid.split(".")
    name = parts[-2] if len(parts[-1]) == 10 and parts[-1].isalnum() else parts[-1]
    rules = [
        ("volume_anomaly_", "volume_anomaly"), ("source_columns_match_", "columns_match(source)"),
        ("no_future_timestamps_stg_orders__etl_loaded_at", "no_future_timestamps(_etl_loaded_at)"),
        ("no_future_timestamps_stg_orders_ordered_at", "no_future_timestamps(ordered_at)"),
        ("values_between_", "values_between"), ("null_rate_below_", "null_rate_below"),
        ("relationships_", "relationships"), ("unique_fct_orders_order_id", "unique(order_id)"),
        ("not_null_fct_orders_customer_id", "not_null(customer_id)"), ("not_null_fct_orders_order_id", "not_null(order_id)"),
    ]
    for prefix, nice in rules:
        if name.startswith(prefix):
            return nice
    return name


# Les quatre contrôles ajoutés après la première matrice (voir l'article) : `--baseline` les exclut pour rejouer les « contrôles de départ ».
ADDED = ["test_name:values_between", "test_name:no_future_timestamps", "test_name:columns_match"]


def one(label, sql, baseline=False):
    for f in ("obs.duckdb", "obs.duckdb.wal"):
        Path(f).unlink(missing_ok=True)
    subprocess.run([sys.executable, "scripts/gen_data.py", "--clean"], check=True, capture_output=True)
    run("seed")
    if sql:
        con = duckdb.connect("obs.duckdb")
        con.sql(sql)
        con.close()
    run("build", "--exclude", "resource_type:seed", "path:models/edge", *(ADDED if baseline else []))
    rr = json.loads(Path("target/run_results.json").read_text())["results"]
    bad, errors = [], []
    for r in rr:
        uid, st = r["unique_id"], str(r["status"]).lower()
        if uid.startswith(("test.", "unit_test.")) and st == "skipped":
            continue   # ignoré parce qu'un amont a échoué : ce n'est pas une détection
        if uid.startswith(("test.", "unit_test.")) and st not in ("pass", "success"):
            bad.append(f"{short(uid)} ({'warn' if st.startswith('warn') else 'fail' if st.startswith('fail') else st})")
        elif uid.startswith("model.") and st in ("error",):
            errors.append(uid.split(".")[-1])
    run("source", "freshness")
    fr = json.loads(Path("target/sources.json").read_text())["results"][0]
    fstat = str(fr.get("status", "?")).lower()
    age = fr.get("max_loaded_at_time_ago_in_s")
    fresh = {"pass": "Passed", "warn": "Warned", "error": "Stale"}.get(fstat, fstat)
    if fstat != "pass":
        bad.append(f"freshness ({fresh})")
    elif age is not None and (age < 0 or age > 10**8):
        fresh = f"Passed, âge incohérent ({age:.0f} s)"
    return {"mutation": label, "tests": sorted(set(bad)), "build_errors": errors, "freshness": fresh,
            "freshness_age_s": age}


if __name__ == "__main__":
    baseline = "--baseline" in sys.argv   # contrôles de départ seulement (sans les quatre ajoutés)
    out = [one(label, sql, baseline) for label, sql in MUTATIONS]
    Path("mutations_results_baseline.json" if baseline else "mutations_results.json").write_text(json.dumps(out, indent=2, ensure_ascii=False))
    print(f"{'Altération':62} | Ce qui réagit")
    print("-" * 120)
    undetected = 0
    for o in out[1:]:
        reacts = list(o["tests"]) + [f"ERREUR modèle {e}" for e in o["build_errors"]]
        if not reacts:
            undetected += 1
        flag = ", ".join(reacts) if reacts else "AUCUN CONTRÔLE"
        extra = "  [fraîcheur: " + o["freshness"] + "]" if o["freshness"].startswith("Passed, ") else ""
        print(f"{o['mutation'][:62]:62} | {flag}{extra}")
    print(f"\nRéférence : {out[0]['tests'] or 'tous les contrôles passent'}")
    print(f"{len(out) - 1} altérations, {len(out) - 1 - undetected} détectées, {undetected} passées sous tous les contrôles.")
