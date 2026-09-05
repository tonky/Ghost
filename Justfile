# SPDX-FileCopyrightText: 2026 Ghost Foundation
# SPDX-License-Identifier: MIT

# ==============================================================================
# Ghost Monorepo Automation & Development Recipes (enve + Just)
# ==============================================================================

# Global development flags
export FORCE_COLOR := "1"
export DISABLE_V8_COMPILE_CACHE := "1"
export NX_NATIVE_COMMAND_RUNNER := "false"

# Explicit configuration for rootless MySQL over UNIX domain socket
DB_CLIENT := "mysql2"
DB_SOCKET := invocation_directory() / ".enve/run/mysql.sock"
DB_USER := "root"
DB_PASS := "root"
DB_NAME := "ghost_dev"
DB_CHARSET := "utf8mb4"

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
    if [ ! -d ".enve/data/mysql/mysql" ]; then
        echo "📦 Initializing clean rootless MySQL 8 database..."
        mkdir -p .enve/data/mysql .enve/run
        mysqld --initialize-insecure --datadir="{{ invocation_directory() }}/.enve/data/mysql"
    fi

# Boot rootless background services (MySQL 8, Redis 7, Mailpit)
db-up: db-init
    @if [ ! -S "{{ DB_SOCKET }}" ] || ! mysqladmin -u root -proot --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1; then \
        echo "🚀 Launching rootless MySQL over UNIX domain socket..."; \
        rm -f "{{ DB_SOCKET }}" "{{ DB_SOCKET }}.lock"; \
        mysqld --datadir="{{ invocation_directory() }}/.enve/data/mysql" --socket="{{ DB_SOCKET }}" --skip-networking --mysqlx=0 > .enve/run/mysqld.log 2>&1 & \
        for i in $$(seq 1 30); do \
            if mysqladmin --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1 || mysqladmin -u root -proot --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1; then \
                break; \
            fi; \
            sleep 0.1; \
        done; \
        mysql -u root --socket="{{ DB_SOCKET }}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'; FLUSH PRIVILEGES; CREATE DATABASE IF NOT EXISTS ghost_dev;" >/dev/null 2>&1 || true; \
        echo "✅ Rootless MySQL active on UNIX socket (Zero TCP Port Collisions)."; \
    fi

# Gracefully stop all background services
db-down:
    @echo "🛑 Stopping background microservices..."
    @if [ -S "{{ DB_SOCKET }}" ]; then \
        mysqladmin -u root -proot --socket="{{ DB_SOCKET }}" shutdown >/dev/null 2>&1 || true; \
        rm -f "{{ DB_SOCKET }}" "{{ DB_SOCKET }}.lock"; \
    fi

# Launch local Ghost development watchers with rootless MySQL and Redis
dev: db-up
    @echo "👻 Starting Ghost Monorepo Development Environment..."
    database__client="{{ DB_CLIENT }}" \
    database__connection__socketPath="{{ DB_SOCKET }}" \
    database__connection__user="{{ DB_USER }}" \
    database__connection__password="{{ DB_PASS }}" \
    database__connection__database="{{ DB_NAME }}" \
    database__connection__charset="{{ DB_CHARSET }}" \
    pnpm nx run ghost-monorepo:docker:dev:public

# ------------------------------------------------------------------------------
# Database Operations (Zero Host Port 3306 Collisions via UNIX Domain Socket)
# ------------------------------------------------------------------------------

# Execute database migrations directly over the isolated UNIX domain socket
migrate-db: db-up
    @echo "🔄 Running knex-migrator database migrations..."
    database__client="{{ DB_CLIENT }}" \
    database__connection__socketPath="{{ DB_SOCKET }}" \
    database__connection__user="{{ DB_USER }}" \
    database__connection__password="{{ DB_PASS }}" \
    database__connection__database="{{ DB_NAME }}" \
    database__connection__charset="{{ DB_CHARSET }}" \
    pnpm --filter ghost exec knex-migrator migrate

# Sub-second fast database reset directly over UNIX socket (eliminating docker exec)
reset-db: db-up
    @echo "⚡ Resetting database schema..."
    database__client="{{ DB_CLIENT }}" \
    database__connection__socketPath="{{ DB_SOCKET }}" \
    database__connection__user="{{ DB_USER }}" \
    database__connection__password="{{ DB_PASS }}" \
    database__connection__database="{{ DB_NAME }}" \
    database__connection__charset="{{ DB_CHARSET }}" \
    pnpm --filter ghost exec knex-migrator reset
    database__client="{{ DB_CLIENT }}" \
    database__connection__socketPath="{{ DB_SOCKET }}" \
    database__connection__user="{{ DB_USER }}" \
    database__connection__password="{{ DB_PASS }}" \
    database__connection__database="{{ DB_NAME }}" \
    database__connection__charset="{{ DB_CHARSET }}" \
    pnpm --filter ghost exec knex-migrator init

# Populate local development database with sample members and posts
seed-data: db-up
    @echo "🌱 Seeding local database..."
    database__client="{{ DB_CLIENT }}" \
    database__connection__socketPath="{{ DB_SOCKET }}" \
    database__connection__user="{{ DB_USER }}" \
    database__connection__password="{{ DB_PASS }}" \
    database__connection__database="{{ DB_NAME }}" \
    database__connection__charset="{{ DB_CHARSET }}" \
    node ghost/core/index.js generate-data --clear-database --quantities members:1000,posts:100 --seed 123

# ------------------------------------------------------------------------------
# Code Quality, Formatting, Lints & Security
# ------------------------------------------------------------------------------

# Check code formatting with oxfmt (sub-second Rust formatter)
fmt-check:
    pnpm format:check

# Automatically format code with oxfmt
fmt:
    pnpm format

# Run package standards verification
lint-pkgs:
    pnpm lint:packages

# Run Nx monorepo boundary and ESLint checks
lint:
    pnpm nx run-many -t lint

# Run all quality gates (formatting, package standards, and unit tests)
check: fmt-check lint-pkgs test-unit
    @echo "✅ All local developer checks passed!"

# ------------------------------------------------------------------------------
# Test Suites
# ------------------------------------------------------------------------------

# Run Ghost Core server unit tests (Vitest)
test-unit:
    pnpm nx run ghost:test:unit

# Run all monorepo package unit tests
test-unit-all:
    pnpm test:unit

# Run TypeScript typechecks across affected packages
test-types:
    pnpm test:types

# Run database integration tests against rootless MySQL socket
test-integration: db-init
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .enve/run .enve/data/mysql
    rm -f "{{ DB_SOCKET }}" "{{ DB_SOCKET }}.lock"
    mysqld --datadir="{{ invocation_directory() }}/.enve/data/mysql" --socket="{{ DB_SOCKET }}" --skip-networking --mysqlx=0 > .enve/run/mysqld.log 2>&1 &
    MYSQL_PID=$!
    trap 'kill $MYSQL_PID 2>/dev/null || true; rm -f "{{ DB_SOCKET }}" "{{ DB_SOCKET }}.lock"' EXIT
    for i in $(seq 1 30); do
        if mysqladmin --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1 || mysqladmin -u root -proot --socket="{{ DB_SOCKET }}" ping >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    mysql -u root --socket="{{ DB_SOCKET }}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'; FLUSH PRIVILEGES; CREATE DATABASE IF NOT EXISTS ghost_dev;" >/dev/null 2>&1 || true
    echo "✅ Rootless MySQL active on UNIX socket (Zero TCP Port Collisions)."
    database__client="{{ DB_CLIENT }}" \
    database__connection__socketPath="{{ DB_SOCKET }}" \
    database__connection__user="{{ DB_USER }}" \
    database__connection__password="{{ DB_PASS }}" \
    database__connection__database="{{ DB_NAME }}" \
    database__connection__charset="{{ DB_CHARSET }}" \
    pnpm --filter ghost exec vitest run -c vitest.config.db.ts --project integration test/integration/services/offers-api.test.js

# Run MySQL acceptance tests against the isolated rootless MySQL socket
test-acc: db-up
    database__client="{{ DB_CLIENT }}" \
    database__connection__socketPath="{{ DB_SOCKET }}" \
    database__connection__user="{{ DB_USER }}" \
    database__connection__password="{{ DB_PASS }}" \
    database__connection__database="{{ DB_NAME }}" \
    database__connection__charset="{{ DB_CHARSET }}" \
    pnpm nx run ghost:test:acceptance
