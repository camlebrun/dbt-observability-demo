"""Teste les tests : compare le statut obtenu de chaque contrôle au statut attendu.

Chaque test déclare son statut attendu dans `config.meta.expect` (pass | warn | fail).
Un contrôle sans déclaration est attendu en `pass`. Le script lit target/manifest.json
et target/run_results.json, affiche l'écart et sort en erreur s'il y en a un.
"""
import json
import re
import sys
from pathlib import Path

target = Path(sys.argv[1] if len(sys.argv) > 1 else "target")
manifest = json.loads((target / "manifest.json").read_text())
results = json.loads((target / "run_results.json").read_text())["results"]

def expected(uid):
    node = manifest.get("nodes", {}).get(uid) or manifest.get("unit_tests", {}).get(uid) or {}
    meta = (node.get("config") or {}).get("meta") or node.get("meta") or {}
    return meta.get("expect", "pass")

def normalise(status):
    s = str(status).lower()
    return {"warned": "warn", "failed": "fail", "passed": "pass"}.get(s, s)

rows, bad = [], 0
for r in results:
    uid = r["unique_id"]
    if not uid.startswith(("test.", "unit_test.")):
        continue
    want, got = expected(uid), normalise(r["status"])
    ok = want == got
    bad += not ok
    parts = uid.split(".")
    name = parts[-2] if re.fullmatch(r"[0-9a-f]{10}", parts[-1]) else parts[-1]   # retire le suffixe de hachage
    rows.append((("OK " if ok else "ECART"), want, got, name))

width = max(len(x[3]) for x in rows)
for ok, want, got, name in sorted(rows, key=lambda x: (x[0] != "ECART", x[3])):
    print(f"{ok:5}  attendu={want:4}  obtenu={got:5}  {name:<{width}}")
print(f"\n{len(rows)} contrôles, {bad} écart(s) entre statut attendu et statut obtenu.")
sys.exit(1 if bad else 0)
