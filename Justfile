# SPDX-FileCopyrightText: 2026 Ghost Foundation
# SPDX-License-Identifier: MIT

# ==============================================================================
# Ghost Monorepo Automation & Development Recipes (enve + Just)
# Exact Parity with Ghost Upstream package.json and CI Workflows
# ==============================================================================

# Global development flags (matching Ghost root env)
export FORCE_COLOR := "1"
export DISABLE_V8_COMPILE_CACHE := "1"
export NX_NATIVE_COMMAND_RUNNER := "false"
export TZ := "America/New_York"
export NODE_OPTIONS := "--conditions=source"

# Explicit configuration for rootless MySQL over UNIX domain socket
DB_CLIENT := "mysql2"
DB_SOCKET := invocation_directory() / ".enve/run/mysql.sock"
DB_USER := "root"
DB_PASS := "root"
DB_NAME := "ghost_dev"
DB_CHARSET := "utf8mb4"
DB_DATADIR := env_var_or_default("MYSQL_DATADIR", invocation_directory() / ".enve/data/mysql")

# DB environment injection prefix for recipes requiring MySQL database
DB_ENV := "database__client=" + DB_CLIENT + " database__connection__socketPath=" + DB_SOCKET + " database__connection__user=" + DB_USER + " database__connection__password=" + DB_PASS + " database__connection__database=" + DB_NAME + " database__connection__charset=" + DB_CHARSET

# Display all available recipes and descriptions
default:
    @just --list

# ------------------------------------------------------------------------------
# Daily Development & Rootless Service Management
# ------------------------------------------------------------------------------

# Initialize local MySQL database storage if not already present
db-init:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "{{ DB_DATADIR }}/mysql" ]; then
        echo "📦 Initializing clean rootless MySQL 8 database in {{ DB_DATADIR }}..."
        mkdir -p "{{ DB_DATADIR }}" .enve/run
        mysqld --no-defaults --initialize-insecure --datadir="{{ DB_DATADIR }}"
    fi

# Boot rootless background services (MySQL 8, Redis 7, Mailpit)
db-up: db-init
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -S "{{ DB_SOCKET }}" ] || ! mysqladmin -u root -proot --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1; then
        echo "🚀 Launching rootless MySQL over UNIX domain socket..."
        rm -f "{{ DB_SOCKET }}" "{{ DB_SOCKET }}.lock"
        setsid mysqld --no-defaults --datadir="{{ DB_DATADIR }}" --socket="{{ DB_SOCKET }}" --skip-networking --mysqlx=0 --innodb-flush-log-at-trx_commit=0 --innodb-buffer-pool-size=512M --innodb-log-buffer-size=64M > .enve/run/mysqld.log 2>&1 < /dev/null &
        for i in $(seq 1 30); do
            if mysqladmin --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1 || mysqladmin -u root -proot --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1; then
                break
            fi
            sleep 0.1
        done
        mysql -u root --socket="{{ DB_SOCKET }}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'; FLUSH PRIVILEGES; CREATE DATABASE IF NOT EXISTS ghost_dev;" >/dev/null 2>&1 || true
        echo "✅ Rootless MySQL active on UNIX socket (Zero TCP Port Collisions)."
    else
        echo "✅ Rootless MySQL is already running."
    fi

# Gracefully stop all background services
db-down:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🛑 Stopping background microservices..."
    if [ -S "{{ DB_SOCKET }}" ]; then
        mysqladmin -u root -proot --socket="{{ DB_SOCKET }}" shutdown >/dev/null 2>&1 || true
        rm -f "{{ DB_SOCKET }}" "{{ DB_SOCKET }}.lock"
        echo "✅ Rootless MySQL stopped."
    else
        echo "ℹ️ Rootless MySQL was not running."
    fi

# Launch local Ghost development watchers with rootless MySQL
dev: db-up
    @echo "👻 Starting Ghost Monorepo Development Environment..."
    {{ DB_ENV }} pnpm nx run ghost-monorepo:docker:dev:public

# ------------------------------------------------------------------------------
# Database Operations (Exact Parity with Upstream Scripts, Zero Docker Overhead)
# ------------------------------------------------------------------------------

# Execute database migrations directly over the isolated UNIX domain socket (parity: pnpm migrate:db)
migrate-db: db-up
    @echo "🔄 Running knex-migrator database migrations..."
    {{ DB_ENV }} pnpm --filter ghost exec knex-migrator migrate

# Rollback last database migration (parity: pnpm rollback:db)
rollback-db: db-up
    @echo "⏪ Rolling back last database migration..."
    {{ DB_ENV }} pnpm --filter ghost exec knex-migrator rollback

# Reset database schema and initialize fresh (parity: pnpm reset:db)
reset-db: db-up
    @echo "⚡ Resetting database schema..."
    {{ DB_ENV }} pnpm --filter ghost exec knex-migrator reset
    {{ DB_ENV }} pnpm --filter ghost exec knex-migrator init

# Populate local development database with sample members and posts (parity: pnpm reset:data)
seed-data: db-up
    @echo "🌱 Seeding local database with sample members and posts..."
    {{ DB_ENV }} node ghost/core/index.js generate-data --clear-database --quantities members:1000,posts:100 --seed 123

# Alias for seed-data matching Ghost upstream naming
reset-data: seed-data

# Reset database with empty dataset (parity: pnpm reset:data:empty)
reset-data-empty: db-up
    @echo "🌱 Clearing data and initializing empty seed..."
    {{ DB_ENV }} node ghost/core/index.js generate-data --clear-database --quantities members:0,posts:0 --seed 123

# Reset database with extra large dataset (parity: pnpm reset:data:xxl)
reset-data-xxl: db-up
    @echo "🌱 Generating XXL dataset for scale testing..."
    {{ DB_ENV }} node ghost/core/index.js generate-data --clear-database --quantities members:2000000,posts:0,emails:0,members_stripe_customers:0,members_login_events:0,members_status_events:0 --seed 123

# Seed multiple subscription scenarios (parity: pnpm seed:multi-sub-scenarios)
seed-multi-sub: db-up
    {{ DB_ENV }} node ghost/core/scripts/seed-multi-sub-scenarios.js

# ------------------------------------------------------------------------------
# Code Quality, Formatting, Lints & Security
# ------------------------------------------------------------------------------

# Automatically format code with oxfmt (parity: pnpm format)
fmt:
    pnpm format

# Check code formatting with oxfmt (parity: pnpm format:check)
fmt-check:
    pnpm format:check

# Run monorepo package standards verification (parity: pnpm lint:packages)
lint-pkgs:
    pnpm lint:packages

# Run architecture boundary checks (parity: pnpm lint:boundaries)
lint-boundaries:
    pnpm lint:boundaries

# Run documentation linting and guidance checks (parity: pnpm lint:docs)
lint-docs:
    pnpm lint:docs

# Run full monorepo lint suite (parity: pnpm lint)
lint:
    pnpm lint

# Fast pre-commit gatekeeper check (oxfmt + package check + core unit tests + integration smoke)
check-fast: fmt-check lint-pkgs test-unit test-integration-smoke
    @echo "✅ Fast PR gatekeeper checks passed!"

# Full repository validation pipeline (parity: pnpm check)
check:
    pnpm check

# ------------------------------------------------------------------------------
# Test Suites (Exact Parity with Ghost Root and Ghost Core Test Targets)
# ------------------------------------------------------------------------------

# Run full monorepo test suite (parity: pnpm test)
test:
    pnpm test

# Build frontend assets and card manifests (parity: ghost build:assets)
build-assets:
    pnpm --filter ghost build:assets

# Run Ghost Core server unit tests (vitest run - 8,500+ tests in ~25s)
test-unit: build-assets
    pnpm --filter ghost test:unit

# Run monorepo unit tests across all 35 packages (parity: pnpm test:unit)
test-unit-all:
    pnpm test:unit

# Run TypeScript typechecks across the monorepo (parity: pnpm test:types)
test-types:
    pnpm test:types

# Run TypeScript typechecks specifically for Ghost Core (parity: ghost test:types)
test-types-core:
    pnpm --filter ghost test:types

# Run full Ghost Core database integration test suite against rootless MySQL socket (56 files / 514 tests)
test-integration *args: db-up build-assets
    {{ DB_ENV }} pnpm --filter ghost exec vitest run -c vitest.config.db.ts --project integration {{ args }}

# Run fast database integration smoke test (offers API - 2 tests in ~8s)
test-integration-smoke: db-up build-assets
    {{ DB_ENV }} pnpm --filter ghost exec vitest run -c vitest.config.db.ts --project integration test/integration/services/offers-api.test.js

# Run Ghost Core database E2E tests against rootless MySQL socket (parity: ghost test:e2e)
test-e2e *args: db-up build-assets
    {{ DB_ENV }} pnpm --filter ghost exec vitest run -c vitest.config.db.ts --project e2e --project e2e-api --project e2e-isolated {{ args }}

# Run Ghost Core legacy database tests against rootless MySQL socket (parity: ghost test:legacy)
test-legacy *args: db-up build-assets
    {{ DB_ENV }} pnpm --filter ghost exec vitest run -c vitest.config.db.ts --project legacy {{ args }}

# Run all Ghost Core test suites together (parity: ghost test:all)
test-all: db-up build-assets
    {{ DB_ENV }} pnpm --filter ghost test:all


