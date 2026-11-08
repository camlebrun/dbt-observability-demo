#!/bin/sh
# Rejoue la matrice de seize altérations avec des tests de PACKAGES (dbt_utils, dbt_expectations)
# à la place des macros maison. Travaille sur une copie jetable : le projet n'est pas modifié.
# Exige le réseau (dbt deps) et le module Python `duckdb`. Résultat : mutations_results_packages.json
set -e
SRC=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
tar -C "$SRC" --exclude=.git --exclude=target --exclude=logs --exclude=dbt_packages \
    --exclude='*.duckdb' --exclude='*.wal' --exclude='seeds/raw_*.csv' -cf - . | tar -C "$TMP" -xf -
cp "$SRC/extras/package_suite/packages.yml" "$TMP/packages.yml"
cp "$SRC/extras/package_suite/_sources.yml" "$TMP/models/staging/_sources.yml"
cp "$SRC/extras/package_suite/_staging.yml" "$TMP/models/staging/_staging.yml"
cp "$SRC/extras/package_suite/_marts.yml"   "$TMP/models/marts/_marts.yml"
rm -f "$TMP"/tests/*.sql "$TMP"/mutations_results*.json    # les tests singuliers sont remplacés par ceux des packages
"${PYTHON:-python3}" - "$TMP/dbt_project.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# dbt_expectations exige cette variable (dbt_date)
s = s.replace("vars:\n", 'vars:\n  "dbt_date:time_zone": "UTC"\n', 1)
open(p, "w", encoding="utf-8").write(s)
PY
cd "$TMP"
export DBT_PROFILES_DIR=.
${DBT:-dbt} deps
"${PYTHON:-python3}" scripts/mutate.py "$@"
for f in mutations_results*.json; do cp "$f" "$SRC/${f%.json}_packages.json"; done
echo "copie jetable : $TMP"
