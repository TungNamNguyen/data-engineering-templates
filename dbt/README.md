# Production dbt Monorepo Template

[![dbt version](https://img.shields.io/badge/dbt--core-1.8+-orange.svg?style=flat&logo=dbt)](https://getdbt.com)
[![Dependency Management](https://img.shields.io/badge/managed_by-uv-purple.svg?style=flat)](https://github.com/astral-sh/uv)
[![Code Style](https://img.shields.io/badge/sqlfluff-linted-green.svg)](https://docs.sqlfluff.com/)

A true **production-grade monorepo template** for dbt. It features a blazing-fast Python environment managed by `uv`, unified tooling (`sqlfluff`, `Makefile`), and a shared `profiles.yml` supporting multi-environment deployments.

The included project `dbt-postgres/` acts as a reference implementation, demonstrating the industry-standard **staging → intermediate → marts** layered architecture with a realistic multi-source ecommerce domain (Shopify + Stripe).

---

## Table of Contents
- [Architecture & DAG](#-architecture--dag)
- [Project Layout](#-project-layout)
- [Production Features](#-production-features)
- [Naming Conventions](#-naming-conventions)
- [Quick Start (Step-by-step)](#-quick-start-step-by-step)
- [Multi-environment Configuration](#-multi-environment-configuration)
- [Starting a New Project](#-starting-a-new-project-from-this-template)

---

## Architecture & DAG

This template enforces a strict separation of concerns through three distinct layers:

| Layer | Prefix | Schema | Materialization | Purpose |
|:---|:---|:---|:---|:---|
| **1. Staging** | `stg_` | `staging` | `view` | 1:1 mapped to sources. Renames columns, casts types, trims whitespace. **No joins.** |
| **2. Intermediate** | `int_` | `intermediate` | `ephemeral` | Where the heavy lifting happens. Cross-source joins & complex business logic. |
| **3. Marts** | `dim_` / `fct_` | `marts` | `table` | Clean, documented, data-contract-enforced tables reading for BI consumption. |

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
dbt/                             ← Monorepo Root
├── pyproject.toml               # Python dependencies (dbt, sqlfluff)
├── uv.lock                      # Deterministic dependency lockfile
├── profiles.yml                 # Shared dev/prod/ci targets for all projects
├── .env.example                 # Template for database credentials
├── Makefile                     # Task runner (make help, make build, make docs)
├── .gitignore
│
└── dbt-postgres/                ← The dbt Project
    ├── dbt_project.yml
    ├── packages.yml             # dbt_utils + dbt_expectations
    ├── .sqlfluff                # Unified linting rules
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
    │       ├── core/            #  ├── schema.yml (+contract enforced)
    │       │                    #  └── dim_*, fct_*
    │       └── finance/         
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
| **Marts Configs** | `schema.yml` | `schema.yml` |

---

## Quick Start (Step-by-step)

This project abandons traditional `pip`/`venv` workflows in favor of **[uv](https://docs.astral.sh/uv/)**, making dependency resolution and environment creation nearly instantaneous.

### 1. Prerequisites
- **Python**: Ensure you have Python installed on your system.
- **uv**: Install via pip (the fastest method):
  ```bash
  pip install uv
  ```
- **Postgres**: Make sure you have a local Postgres instance running (either via Docker or native application).

### 2. Lock and Sync Dependencies
The project dependencies (`dbt-core`, `dbt-postgres`, `sqlfluff`) are centralized in `pyproject.toml`.

```bash
# Optional: Lock the exact dependencies into uv.lock explicitly
uv lock

# Create the isolated .venv and install everything
uv sync

# Note: You can also just run `make install` which triggers uv sync automatically.
```

### 3. Configure Database Credentials
To keep credentials secure, this monorepo uses a shared `profiles.yml` at the root directory that interpolates variables from a local `.env` file.

```bash
# 1. Create your local env file from the template
cp .env.example .env

# 2. Edit .env with your actual database credentials
nano .env

# 3. Load the variables into your active shell session (CRITICAL)
set -a; source .env; set +a
```

### 4. Verify the Installation
Test the dbt connection to your warehouse. You can use the `Makefile` or invoke dbt through `uv`.

```bash
# Download dbt packages (dbt_utils, dbt_expectations)
make deps

# Test the connection to the database
uv run dbt debug --project-dir dbt-postgres --profiles-dir .
```

### 5. Build the Data Warehouse
Run the unified pipeline. This single command will compile everything in the correct order: load seeds, snapshot slowly changing dimensions, run staging/intermediate/marts, and execute all tests.

```bash
make build
```

### 6. Explore the Lineage
To visually explore the DAG, documentation, and tests:
```bash
make docs
```
*Navigates to `http://localhost:8080` in your browser.*

> **Tip:** Run `make help` at any time to see standard automation scripts (linting, testing, CI).

---

## Multi-environment Configuration

Controlled entirely by your `.env` variables and the `profiles.yml` target:

| Target | Usage | Threads | Notes |
|---|---|---|---|
| `dev` | Local development (default) | 4 | SSL: `prefer` |
| `prod` | Production deployment | 8 | SSL: `require` |
| `ci` | CI/CD pipelines | 4 | Dynamically targets schema: `ci_<pipeline_id>` |

---

## Starting a New Project from this Template

If you are cloning this repository to build your own warehouse:

1. Copy the entire `dbt/` directory to your new codebase.
2. Rename `dbt-postgres/` to match your actual project name.
3. Update `dbt_project.yml`: Change `name` and update the `profile` key.
4. Add your new profile mapping in `profiles.yml`.
5. Inside the `models/staging` layer, delete `shopify/` and `stripe/` and replace them with your actual source systems adhering to the naming conventions.
6. Run `make build` to verify the refactor.

---

## Further Reading

- [dbt Best Practices](https://docs.getdbt.com/best-practices)
- [How we structure our dbt projects](https://docs.getdbt.com/best-practices/how-we-structure-our-dbt-projects)
- [dbt Data Contracts](https://docs.getdbt.com/docs/collaborate/govern/model-contracts)
- [SQLFluff Linter](https://docs.sqlfluff.com/en/stable/)
