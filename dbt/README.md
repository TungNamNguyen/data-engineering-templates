# Production dbt Monorepo Template

[![dbt version](https://img.shields.io/badge/dbt--core-1.9+-orange.svg?style=flat&logo=dbt)](https://getdbt.com)
[![Dependency Management](https://img.shields.io/badge/managed_by-uv-purple.svg?style=flat)](https://github.com/astral-sh/uv)
[![Code Style](https://img.shields.io/badge/sqlfluff-linted-green.svg)](https://docs.sqlfluff.com/)

A **production-grade dbt template**. It features a blazing-fast Python environment managed by `uv`, unified tooling (`sqlfluff`), and a self-contained `dbt-postgres/` project with `profiles.yml` supporting multi-environment deployments.

`dbt-postgres/` is the reference implementation — kept self-contained so it can be copied as-is into a new repo — demonstrating the industry-standard **staging → intermediate → marts** layered architecture with a realistic multi-source ecommerce domain (Shopify + Stripe).

---

## Table of Contents
- [Architecture & DAG](#architecture--dag)
- [Project Layout](#project-layout)
- [Production Features](#production-features)
- [Naming Conventions](#naming-conventions)
- [Quick Start (Step-by-step)](#quick-start-step-by-step)
- [Command Reference](#command-reference)
- [Multi-environment Configuration](#multi-environment-configuration)
- [Starting a New Project](#starting-a-new-project-from-this-template)

---

## Architecture & DAG

This template enforces a strict separation of concerns through three distinct layers:

| Layer | Prefix | Schema | Materialization | Purpose |
|:---|:---|:---|:---|:---|
| **1. Staging** | `stg_` | `staging` | `view` | 1:1 mapped to sources. Renames columns, casts types, trims whitespace. **No joins.** |
| **2. Intermediate** | `int_` | `intermediate` | `view` | Where the heavy lifting happens. Cross-source joins & complex business logic. Queryable for debugging. |
| **3. Marts** | `dim_` / `fct_` | `marts` | `table` | Clean, documented, data-contract-enforced tables ready for BI consumption. |

### The Data Flow

```text
Shopify (4 tables)           Stripe (1 table)
       │                            │
       ▼                            ▼
[ stg_shopify_* ]             [ stg_stripe_* ]
       │                            │
       └──────────────┬─────────────┘
                      ▼
[ int_orders_enriched ] & [ int_customer_orders ]
                      │
   ┌──────────────────┼──────────────────┐
   ▼                  ▼                  ▼
[ dim_* ]          [ fct_* ]      [ fct_payments ]
   │                  │                  │
   └─────────► [ BI Dashboards / Exposures ]
```

---

## Project Layout

```text
dbt/                             ← Template Root
├── pyproject.toml               # Python dependencies (dbt, sqlfluff)
├── uv.lock                      # Deterministic dependency lockfile
├── .gitignore
│
└── dbt-postgres/                ← The dbt Project (self-contained)
    ├── dbt_project.yml
    ├── profiles.yml             # dev/prod/ci targets
    ├── .env.example             # Template for database credentials
    ├── packages.yml             # dbt_utils + dbt_expectations
    ├── .sqlfluff                # Linting rules
    │
    ├── models/
    │   ├── staging/             # Grouped by source system
    │   │   ├── shopify/         #  ├── _shopify__sources.yml (inputs)
    │   │   │                    #  ├── _shopify__models.yml (outputs)
    │   │   │                    #  └── stg_shopify__*.sql
    │   │   └── stripe/
    │   │
    │   ├── intermediate/        # Flat directory — logic crosses sources
    │   │   └── schema.yml
    │   │
    │   └── marts/               # Grouped by business domain
    │       ├── _groups.yml      # Defines ownership (core, finance)
    │       ├── _exposures.yml   # Documents downstream dashboards
    │       ├── core/            #  ├── _core__models.yml (+contract enforced)
    │       │                    #  └── dim_*, fct_*
    │       └── finance/         #  ├── _finance__models.yml
    │                            #  └── fct_*
    │
    ├── seeds/                   # Static reference data (e.g. country codes)
    ├── snapshots/               # SCD Type 2 tracking (timestamp & check strategies)
    ├── tests/                   # Singular & Unit tests
    ├── macros/                  # Reusable Jinja snippets (cents_to_dollars)
    └── analyses/                # Ad-hoc analytical queries
```

---

## Production Features

| Feature | Description |
|:---|:---|
| **Multi-source Integration** | Demonstrates cross-joining `shopify` and `stripe` cleanly in the intermediate layer. |
| **Source Freshness** | SLA monitoring configured via `loaded_at_field` in `sources.yml`. |
| **Data Contracts** | `contract.enforced: true` on all mart models guarantees schema stability for BI tools. |
| **Model Groups** | `_groups.yml` establishes strict ownership boundaries (e.g., Core team vs Finance team). |
| **Active Snapshots** | Includes real-world SCD Type 2 configs using both `timestamp` and `check` strategies. |
| **Unit Testing** | Leverages dbt 1.8+ static-input logic validation in `tests/unit_tests.yml`. |
| **Exposures** | Clearly documents which dashboards break if a `dim_` or `fct_` model is altered. |
| **CI/CD Ready** | `profiles.yml` handles isolated target schemas dynamically based on pipeline IDs. |

---

## Naming Conventions

This project strictly adheres to dbt Labs 2025 conventions:

| Object | Convention | Example |
|---|---|---|
| **Source** | `source('<system>', '<table>')` | `source('shopify', 'raw_customers')` |
| **Staging model** | `stg_<source>__<entity>` | `stg_shopify__customers` |
| **Intermediate model** | `int_<description>` | `int_orders_enriched` |
| **Fact table** | `fct_<noun>` | `fct_orders`, `fct_payments` |
| **Dimension table**| `dim_<noun>` | `dim_customers`, `dim_products` |
| **Snapshot** | `scd_<entity>` | `scd_products` |
| **Seed** | `seed_<noun>` | `seed_country_codes` |
| **Staging Configs**| `_<source>__sources/models.yml`| `_shopify__sources.yml` |
| **Marts Configs** | `_<domain>__models.yml` | `_core__models.yml` |

> **Why two YAML filename conventions?** Staging is grouped per source system, so filenames mirror the model names (`stg_shopify__customers` ↔ `_shopify__models.yml`) — the leading underscore sorts them to the top, and splitting sources/models keeps each file focused. Intermediate and marts have no source namespace, so a generic `schema.yml` is simpler. You may rename them all to `schema.yml` if preferred — dbt reads any `.yml` under `model-paths`.

---

## Quick Start (Step-by-step)

This project uses **[uv](https://docs.astral.sh/uv/)** for dependency management, making environment creation nearly instantaneous.

### 1. Prerequisites
- **Python** 3.10–3.12
- **uv**: `pip install uv` (or [standalone installer](https://docs.astral.sh/uv/getting-started/installation/))
- **Postgres**: a local Postgres instance (Docker or native)

### 2. Install dependencies

```bash
uv sync
```

This reads `pyproject.toml`, resolves everything against the committed `uv.lock`, and creates `.venv/`.

### 3. Configure database credentials

```bash
cd dbt-postgres

# 1. Create your local env file from the template
cp .env.example .env

# 2. Edit .env with your actual database credentials
$EDITOR .env

# 3. Load the variables into your active shell (CRITICAL)
set -a; source .env; set +a
```

`profiles.yml` reads these env vars — dbt auto-discovers it when run from the project directory.

### 4. Install dbt packages & verify the connection

```bash
# Install packages.yml dependencies (dbt_utils, dbt_expectations)
uv run dbt deps

# Test the warehouse connection
uv run dbt debug
```

### 5. Build the warehouse

```bash
uv run dbt build
```

This runs seeds → snapshots → models → tests in dependency order.

### 6. Explore the lineage

```bash
uv run dbt docs generate
uv run dbt docs serve
```

Navigates to `http://localhost:8080`.

---

## Command Reference

Run `uv sync` from the `dbt/` root to install Python deps, then `cd dbt-postgres` for everything else:

| Task | Command |
|:---|:---|
| Install deps (from `dbt/`) | `uv sync` |
| dbt packages | `uv run dbt deps` |
| Load seeds | `uv run dbt seed` |
| Run models | `uv run dbt run` |
| Run tests | `uv run dbt test` |
| Full pipeline (seed + run + test) | `uv run dbt build` |
| Unit tests only | `uv run dbt test --select "test_type:unit"` |
| Source freshness | `uv run dbt source freshness` |
| Generate + serve docs | `uv run dbt docs generate && uv run dbt docs serve` |
| Lint SQL | `uv run sqlfluff lint .` |
| Auto-format SQL | `uv run sqlfluff fix .` |
| Clean build artifacts | `uv run dbt clean` |
| Slim CI (modified + downstream) | `uv run dbt build --select "state:modified+" --defer --state ./prod-manifest` |

For slim CI, `./prod-manifest` must be the manifest produced by the last successful production run — typically downloaded from S3 or a CI artifact store before the build.

---

## Multi-environment Configuration

Controlled entirely by your `.env` variables and the `profiles.yml` target:

| Target | Usage | Threads | Notes |
|---|---|---|---|
| `dev` | Local development (default) | 4 | SSL: `prefer` |
| `prod` | Production deployment | 8 | SSL: `require` |
| `ci` | CI/CD pipelines | 4 | Dynamically targets schema: `ci_<pipeline_id>` |

Select a non-default target with `--target prod` or `--target ci`.

---

## Starting a New Project from this Template

If you are cloning this repository to build your own warehouse:

1. Copy `dbt-postgres/` (and the surrounding `pyproject.toml` / `uv.lock` if you want the same Python env) into your new codebase.
2. Rename `dbt-postgres/` to match your actual project name.
3. Update `dbt_project.yml`: change `name` and update the `profile` key.
4. Update the matching profile name in `profiles.yml`.
5. Inside `models/staging`, delete `shopify/` and `stripe/` and replace them with your actual source systems following the naming conventions above.
6. Run `uv run dbt build` from inside the project directory to verify.

---

## Further Reading

- [dbt Best Practices](https://docs.getdbt.com/best-practices)
- [How we structure our dbt projects](https://docs.getdbt.com/best-practices/how-we-structure-our-dbt-projects)
- [dbt Data Contracts](https://docs.getdbt.com/docs/collaborate/govern/model-contracts)
- [SQLFluff Linter](https://docs.sqlfluff.com/en/stable/)
