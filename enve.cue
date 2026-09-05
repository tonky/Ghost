// SPDX-FileCopyrightText: 2026 Ghost Foundation
// SPDX-License-Identifier: MIT

package devshell

import (
	"github.com/tonky/enve/schema/v1:schema"
	"github.com/tonky/enve/schema/v1/env:env"
	"github.com/tonky/enve/pkgs:pkgs"
)

// -------------------------------------------------------------
// Declarative Ghost Monorepo Developer Environment
// -------------------------------------------------------------

devEnv: schema.#DevEnvironment & {
	name: "ghost-monorepo-dev-environment"
	build: schema.#NodeBuildSpec & {
		pname:   "ghost"
		version: "5.110.0"
		src:     "."
	}
	tools: [
		pkgs.nodejs,
		pkgs.pnpm,
		pkgs.mysql,
		pkgs.redis,
		pkgs.mailpit,
		pkgs.just,
		pkgs.python3,
		pkgs.gcc,
		pkgs.gnumake,
		pkgs.procps,
		pkgs.ripgrep,
		pkgs.git,
	]
	services: {
		mysql: schema.#Service & {
			command: "mysqld --datadir=.enve/data/mysql --socket=.enve/run/mysql.sock --skip-networking --mysqlx=0"
			readinessProbe: {
				command:   "mysqladmin --socket=.enve/run/mysql.sock ping"
				timeoutMs: 5000
			}
		}
		redis: schema.#Service & {
			command: "redis-server --unixsocket .enve/run/redis.sock --port 0 --dir .enve/data/redis --daemonize no"
			readinessProbe: {
				command:   "redis-cli -s .enve/run/redis.sock ping"
				timeoutMs: 3000
			}
		}
		mailpit: schema.#Service & {
			command: "mailpit --smtp 127.0.0.1:1025 --ui 127.0.0.1:8025"
		}
	}
	environment: env.#NodeEnv & env.#PosixEnv & {
		NODE_ENV:                         "development"
		FORCE_COLOR:                      "1"
		DISABLE_V8_COMPILE_CACHE:         "1"
		NX_NATIVE_COMMAND_RUNNER:         "false"
		database__client:                 "mysql2"
		database__connection__socketPath: ".enve/run/mysql.sock"
		database__connection__user:       "root"
		database__connection__password:   "root"
		database__connection__database:   "ghost_dev"
		database__connection__charset:    "utf8mb4"
		mail__transport:                  "SMTP"
		mail__options__host:              "127.0.0.1"
		mail__options__port:              1025
	}
	shellHook: """
		mkdir -p .enve/run .enve/data/mysql .enve/data/redis
		echo "========================================================================"
		echo " 👻 Welcome to the Ghost Developer Environment (enve)                   "
		echo "    Tools: Node.js 22, pnpm, MySQL 8, Redis 7, Mailpit, Python, Just    "
		echo "    Isolation: Rootless UNIX-socket MySQL (Zero Host Port 3306 Collisions) "
		echo "    Automation: run 'just' to list tasks or 'just dev' to start         "
		echo "========================================================================"
		"""
}
