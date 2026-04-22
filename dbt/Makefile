# dbt monorepo — task runner.
#
# DBT_PROFILES_DIR is exported so every project can find the shared
# profiles.yml at the monorepo root, regardless of the cwd dbt commands
# run from. PROJECT picks the dbt project subfolder; override on the
# command line: `make PROJECT=dbt-duckdb build`.

PROJECT ?= dbt-postgres
export DBT_PROFILES_DIR := $(CURDIR)

DBT = cd $(PROJECT) && uv run dbt

.PHONY: help install deps seed run test build docs compile clean \
        lint format freshness unit-test ci slim-ci

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Setup ─────────────────────────────────────────────────────────────────

install:  ## Create .venv and install all deps (incl. dev group)
	uv sync

deps:  ## dbt deps — install packages.yml dependencies
	$(DBT) deps

# ── Pipeline ──────────────────────────────────────────────────────────────

seed:  ## Load CSVs from seeds/ into the warehouse
	$(DBT) seed

run:  ## Build models (views + tables)
	$(DBT) run

test:  ## Run dbt tests (schema + singular)
	$(DBT) test

build:  ## seed + run + test in dependency order
	$(DBT) build

freshness:  ## Check source freshness (requires loaded_at_field)
	$(DBT) source freshness

# ── Testing ───────────────────────────────────────────────────────────────

unit-test:  ## Run unit tests only (dbt >= 1.8)
	$(DBT) test --select "test_type:unit"

# ── CI / CD ───────────────────────────────────────────────────────────────

ci:  ## Full CI pipeline: deps → build (seed + run + test)
	$(DBT) deps && $(DBT) build

slim-ci:  ## Slim CI: only modified models + downstream (requires manifest)
	$(DBT) deps && $(DBT) build --select "state:modified+" --defer --state ./target

# ── Documentation ─────────────────────────────────────────────────────────

docs:  ## Generate and serve lineage docs at http://localhost:8080
	$(DBT) docs generate && $(DBT) docs serve

compile:  ## Compile SQL without executing (writes to target/compiled/)
	$(DBT) compile

# ── Code quality ──────────────────────────────────────────────────────────

lint:  ## sqlfluff lint all projects
	uv run sqlfluff lint $(PROJECT)

format:  ## sqlfluff fix (auto-format) — review diffs before committing
	uv run sqlfluff fix $(PROJECT)

# ── Cleanup ───────────────────────────────────────────────────────────────

clean:  ## Remove target/, dbt_packages/, logs/
	$(DBT) clean
