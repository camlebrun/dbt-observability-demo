# dbt-observability-demo

Projet de démonstration des articles **« Observabilité des données : quels piliers, quelles décisions ? »** (la théorie) et **« Vos contrôles dbt voient-ils vraiment les défauts ? J'ai altéré mes données 16 fois »** (la mesure).

L'idée : un contrôle vert ne prouve que ce qu'il sait chercher. Ce projet couvre les six angles de l'observabilité (fraîcheur, volume, distribution, schéma, lineage, qualité) sur des données **synthétiques**, puis **teste les contrôles eux-mêmes** de deux façons :

1. un garde-fou compare le statut attendu de chaque contrôle au statut obtenu (`scripts/check_expectations.py`) ;
2. une matrice de seize altérations mesure ce que les contrôles voient et ce qu'ils ratent (`scripts/mutate.py`).

Le projet principal n'utilise aucun package dbt (pas de `dbt deps`). Pour `make demo`, il faut dbt (voir Prérequis) et Python 3 ; `make mutations` exige en plus le module `duckdb` (`pip install duckdb`). Seule la cible `make mutations-packages` installe des packages, dans une copie jetable du projet (réseau requis).

**Les contrôles `volume_anomaly`, `values_between`, `no_future_timestamps`, `columns_match` et `null_rate_below` sont des macros maison** (`macros/tests.sql`) : ils ne viennent ni de dbt ni d'un package. Leurs équivalents dans `dbt_utils` 1.4.1 et `dbt_expectations` 0.10.10 sont rejoués sur la même matrice par `make mutations-packages` (configuration dans `extras/package_suite/`).

**Le journal d'exécution est celui d'un projet en production.** `macros/obs/`, `macros/generate_schema_name.sql` et `models/00_observability/` sont copiés **sans modification** (octet pour octet). Un seul fichier est rangé à part, `extras/00_observability/_schema_history.yml` : il utilise `dbt_utils.mutually_exclusive_ranges` et ce projet n'a aucun package.

## Prérequis : quelle version de dbt ?

Les résultats de l'article viennent de **dbt 2.0.9** (la v2, binaire natif, qui embarque ses adaptateurs DuckDB et BigQuery). Il s'installe avec le script officiel décrit dans [la documentation de dbt](https://docs.getdbt.com/docs/fusion/install-fusion-cli) ; vérifiez ensuite avec `dbt --version`. Ce dépôt ne permet pas d'épingler la 2.0.9 : le script d'installation installe la version courante, qui peut donc différer.

`requirements.txt` n'installe **pas** cette version : il épingle **dbt-core 1.12.6** (avec `dbt-duckdb` et `dbt-bigquery`), utilisé dans l'article uniquement pour comparer `rows_affected`. Avec ce seul fichier, `dbt --version` affichera 1.12.6 et les résultats peuvent différer (voir « Limites » plus bas).

## Lancer

```bash
dbt --version                        # attendu : dbt 2.0.9 (voir Prérequis)
export DBT_PROFILES_DIR=.
make demo                            # journal, données, seed, fraîcheur, build, vérification des statuts
make mutations                       # la matrice de seize altérations, avec les quatre contrôles ajoutés (DuckDB, ~3 minutes)
make mutations-baseline              # la même matrice avec les seuls contrôles de départ
make mutations-packages              # la même matrice avec des tests de dbt_utils et dbt_expectations (réseau requis)
make mutations MUTATE_ARGS="--day-offset 1"   # altère la veille (J-1) au lieu du jour courant
```

**Pourquoi `--day-offset 1` ?** Le test de volume de `dbt_expectations` (`expect_column_values_to_be_within_n_moving_stdevs`) n'évalue que les jours clos, jamais le jour courant : une altération du volume du jour lui est invisible par construction. Pour comparer à armes égales, `--day-offset 1` altère la veille, et le test maison `volume_anomaly` est réglé sur la même date (variable `volume_expected_date`). Seules les trois altérations de volume changent ; les résultats sont écrits dans `mutations_results_j1*.json`.

`make journal` (lancé par les deux cibles) crée d'abord les tables du journal : elles sont produites par des *modèles*, alors que les hooks de fin d'exécution les alimentent dès le premier `dbt seed` et échouent si elles n'existent pas.

Résultat attendu de `make demo` : `18 contrôles, 0 écart(s) entre statut attendu et statut obtenu`. Le récapitulatif de dbt compte 35 éléments (seeds, modèles, tests, test unitaire, hooks) : 25 réussis, 2 avertissements, 8 échecs **attendus** (les données contiennent des défauts injectés exprès).

Le projet a été exécuté avec dbt 2.0.9 (la v2) sur DuckDB et sur BigQuery, avec dbt-core 1.12.6 pour comparer `rows_affected`, et avec dbt-core 1.10.13 pour OpenLineage.

### Sur BigQuery

Deux types de colonnes diffèrent, d'où deux variables :

```bash
GCP_PROJECT=mon-projet dbt build --target bigquery \
  --vars '{ts_type: timestamp, double_type: float64}'
```

Le build crée trois datasets : `obs_test` (les modèles), `obs_demo` (le journal : `dbt_results`, `schema_history`) et `dbt_test__audit` (lignes fautives de `store_failures`, nommé sans préfixe à cause de `generate_schema_name`). Les supprimer après usage. Le journal vit dans `obs_demo` et non dans `observability` : c'est le nom du dataset d'un projet réel, et un build ne doit jamais en écrire un. La matrice de mutations ne tourne que sur DuckDB.

Deux pièges du portage sur dbt 2.0.9 : un `var()` dans `+schema` de `dbt_project.yml` ne lit pas les `vars` du projet (le défaut de l'expression doit donc être identique à `vars.observability_dataset`), et `bytes_billed` est vide dans le journal BigQuery.

## Comment lire les résultats

- **`expect`** : chaque test déclare `config.meta.expect` (`pass`, `warn` ou `fail`). Un test sans déclaration est attendu en `pass`. Les modèles de `models/edge/` fabriquent cinq cas limites du test de volume (série constante, déviation unique, table vide, jour absent, historique court).
- **Matrice** : pour chaque altération, le script repart de données saines (`gen_data.py --clean`), charge les seeds, applique **une** altération SQL, lance `dbt build` puis `dbt source freshness`, et liste ce qui réagit. À la fin : combien d'altérations passent sous tous les contrôles.

## Contenu

| Chemin | Rôle |
| --- | --- |
| `scripts/gen_data.py` | données synthétiques en UTC, défauts injectés (ou `--clean`) |
| `scripts/check_expectations.py` | statut attendu contre statut obtenu |
| `scripts/mutate.py` | la matrice de seize altérations (`--baseline`, `--day-offset N`) |
| `scripts/matrix_packages.sh` | la même matrice avec les tests de packages, sur une copie jetable |
| `models/staging/` | sources, fraîcheur, `columns_match` sur la source, modèles de préparation |
| `models/marts/` | contrat de schéma, test unitaire, incrémental (`on_schema_change`) |
| `models/edge/` | cas limites du test de volume |
| `models/exposures.yml` | le tableau de bord, consommateur final (lineage : `dbt ls --select "source:shop.raw_orders+"`) |
| `macros/tests.sql` | `null_rate_below`, `volume_anomaly`, `values_between`, `no_future_timestamps`, `columns_match` |
| `macros/obs/`, `macros/generate_schema_name.sql` | journal d'exécution et historique de schéma (copie de la production) |
| `models/00_observability/` | `dbt_results`, `schema_history`, `mart_test_classification` (copie de la production) |
| `tests/` | tests singuliers, dont la sévérité graduée (`warn_if` / `error_if`) |
| `extras/package_suite/` | tests de `dbt_utils` et `dbt_expectations` rejoués par `make mutations-packages` |
| `extras/` (autres fichiers) | exemples optionnels de tests de packages |

## Limites

- **Données synthétiques, tests écrits pour les défauts injectés** : le projet démontre des mécanismes, pas un taux de détection sur des données réelles.
- **Tests de packages** : ceux de `extras/package_suite/` sont exécutés par `make mutations-packages`. `extras/packages_tests.yml.example` reste un exemple non rejoué.
- **Un réglage par test de package** (deux variantes pour le volume), choisi par l'auteur : ce n'est pas un verdict sur les packages. Avec 15 jours de données, `test_periods` ne peut pas dépasser 7 sans faux positif (historique trop court).
- **Fuseau** : `current_date` suit le fuseau du moteur (local sur DuckDB, UTC sur BigQuery). Une exécution entre minuit et l'heure de décalage local peut déclencher un faux positif du test de volume sur DuckDB.
- Les seize altérations sont un échantillon, pas une mesure de couverture.
