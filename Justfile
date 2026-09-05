# SPDX-FileCopyrightText: 2026 Ghost Foundation
# SPDX-License-Identifier: MIT

# ==============================================================================
# Ghost Monorepo Automation & Development Recipes (enve + Just)
# ==============================================================================

# Explicit environment configuration for rootless MySQL over UNIX domain socket
export database__client := "mysql2"
export database__connection__socketPath := invocation_directory() / ".enve/run/mysql.sock"
export database__connection__user := "root"
export database__connection__password := "root"
export database__connection__database := "ghost_dev"
export database__connection__charset := "utf8mb4"
export FORCE_COLOR := "1"
export DISABLE_V8_COMPILE_CACHE := "1"
export NX_NATIVE_COMMAND_RUNNER := "false"

# Display all available recipes and descriptions
default:
    @just --list

# ------------------------------------------------------------------------------
# Daily Development & Rootless Service Management
# ------------------------------------------------------------------------------

# Initialize local MySQL database storage if not already present
db-init:
    @if [ ! -d ".enve/data/mysql/mysql" ]; then \
        echo "📦 Initializing clean rootless MySQL 8 database..."; \
        mkdir -p .enve/data/mysql .enve/run; \
        mysqld --initialize-insecure --datadir="{{ invocation_directory() }}/.enve/data/mysql" >/dev/null 2>&1; \
    fi

# Boot rootless background services (MySQL 8, Redis 7, Mailpit) via enve process supervisor
db-up: db-init
    @if [ ! -S ".enve/run/mysql.sock" ]; then \
        echo "🚀 Launching rootless MySQL over UNIX domain socket..."; \
        mysqld --datadir="{{ invocation_directory() }}/.enve/data/mysql" --socket="{{ invocation_directory() }}/.enve/run/mysql.sock" --skip-networking --mysqlx=0 > .enve/run/mysqld.log 2>&1 & \
        for i in $(seq 1 30); do \
            if mysqladmin --socket="{{ invocation_directory() }}/.enve/run/mysql.sock" ping >/dev/null 2>&1 || mysqladmin -u root -proot --socket="{{ invocation_directory() }}/.enve/run/mysql.sock" ping >/dev/null 2>&1; then \
                break; \
            fi; \
            sleep 0.1; \
        done; \
        mysql -u root --socket="{{ invocation_directory() }}/.enve/run/mysql.sock" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'; FLUSH PRIVILEGES; CREATE DATABASE IF NOT EXISTS ghost_dev;" >/dev/null 2>&1 || true; \
        echo "✅ Rootless MySQL active on UNIX socket (Zero TCP Port Collisions)."; \
    fi

# Gracefully stop all background services
db-down:
    @echo "🛑 Stopping background microservices..."
    @if [ -S ".enve/run/mysql.sock" ]; then \
        mysqladmin -u root -proot --socket="{{ invocation_directory() }}/.enve/run/mysql.sock" shutdown >/dev/null 2>&1 || true; \
        rm -f .enve/run/mysql.sock; \
    fi

# Launch local Ghost development watchers with rootless MySQL and Redis
dev: db-up
    @echo "👻 Starting Ghost Monorepo Development Environment..."
    pnpm nx run ghost-monorepo:docker:dev:public

# ------------------------------------------------------------------------------
# Database Operations (Zero Host Port 3306 Collisions via UNIX Domain Socket)
# ------------------------------------------------------------------------------

# Execute database migrations directly over the isolated UNIX domain socket
migrate-db: db-up
    @echo "🔄 Running knex-migrator database migrations..."
    pnpm --filter ghost exec knex-migrator migrate

# Sub-second fast database reset directly over UNIX socket (eliminating docker exec)
reset-db: db-up
    @echo "⚡ Resetting database schema..."
    pnpm --filter ghost exec knex-migrator reset
    pnpm --filter ghost exec knex-migrator init

# Populate local development database with sample members and posts
seed-data: db-up
    @echo "🌱 Seeding local database..."
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

# Run all monorepo package unit tests
test-unit:
    pnpm test:unit

# Run Ghost Core server unit tests (Vitest)
test-unit-ghost:
    pnpm nx run ghost:test:unit

# Run TypeScript typechecks across affected packages
test-types:
    pnpm test:types

# Run database integration tests against rootless MySQL socket
test-integration: db-up
    pnpm --filter ghost exec vitest run -c vitest.config.db.ts --project integration

# Run MySQL acceptance tests against the isolated rootless MySQL socket
test-acc: db-up
    pnpm nx run ghost:test:acceptance
