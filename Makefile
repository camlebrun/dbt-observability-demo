DBT ?= dbt
# `make mutations` exige aussi le module `duckdb` (pip install duckdb)
PYTHON ?= python3
TARGET ?= duckdb

setup:            ## dépendances Python
	pip install -r requirements.txt

journal:          ## crée les tables du journal (dbt_results, schema_history) : le hook de fin d'exécution les alimente et échoue si elles n'existent pas
	$(DBT) run --select 00_observability

demo: journal     ## scénario complet sur DuckDB (sans packages : aucun accès réseau requis)
	$(PYTHON) scripts/gen_data.py
	$(DBT) seed
	$(DBT) source freshness
	-$(DBT) build
	$(PYTHON) scripts/check_expectations.py

.PHONY: setup journal demo

mutations: journal ## matrice de mutations : quels contrôles détectent quelle altération ?
	$(PYTHON) scripts/mutate.py

.PHONY: mutations

mutations-baseline: journal ## contrôles de départ seulement (sans les quatre ajoutés)
	$(PYTHON) scripts/mutate.py --baseline

.PHONY: mutations-baseline
