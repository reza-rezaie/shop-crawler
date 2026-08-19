#!/usr/bin/env bash
# Manages a pixi-local Postgres instance for dev/test -- no Docker, no
# system-wide install required. initdb's a data directory under
# data/pgdata/ (gitignored) the first time it's needed, then starts a
# postgres instance listening only on 127.0.0.1 at a fixed, non-default
# port (avoids clashing with any system-wide Postgres on 5432 -- same
# reasoning as dev_server.sh's fixed, unusual port 8934).
#
# Connection defaults (PGHOST/PGPORT/PGDATABASE/PGUSER, plus
# PG_TEST_DATABASE) are exported by scripts/activate.sh on every
# `pixi run`/`pixi shell`, so this script and db.mojo's connect() always
# agree on where the instance lives without duplicating the port/db names
# in two places.
#
# Subcommands:
#   ensure  - init if needed, start if not already running, create the app
#             and test databases if missing (default; safe to call anytime,
#             called automatically by `pixi run dev/serve/test/db-migrate`)
#   start   - alias for ensure
#   stop    - stop the server
#   status  - report whether it's running
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PGDATA_DIR="$(pwd)/data/pgdata"
LOG_FILE="$PGDATA_DIR/server.log"

_is_initialized() {
    [ -f "$PGDATA_DIR/PG_VERSION" ]
}

_is_running() {
    pg_ctl -D "$PGDATA_DIR" status >/dev/null 2>&1
}

_init() {
    if _is_initialized; then
        return 0
    fi
    echo "Initializing local Postgres data directory at $PGDATA_DIR ..."
    mkdir -p "$PGDATA_DIR"
    initdb -D "$PGDATA_DIR" -U "$PGUSER" --auth=trust >/dev/null
    # TCP-only on loopback: no unix socket (sidesteps its path-length limit
    # inside a nested project directory) and never reachable beyond this
    # machine.
    cat >> "$PGDATA_DIR/postgresql.conf" <<EOF

# --- appended by scripts/pg_local.sh ---
listen_addresses = '127.0.0.1'
unix_socket_directories = ''
port = $PGPORT
EOF
}

_start() {
    if _is_running; then
        return 0
    fi
    echo "Starting local Postgres on $PGHOST:$PGPORT ..."
    pg_ctl -D "$PGDATA_DIR" -l "$LOG_FILE" start >/dev/null
    for _ in $(seq 1 50); do
        if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "SELECT 1" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    echo "Postgres did not become ready in time -- check $LOG_FILE" >&2
    exit 1
}

_createdb_if_missing() {
    local name="$1"
    if ! psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '$name'" | grep -q 1; then
        echo "Creating database '$name' ..."
        createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$name"
    fi
}

_ensure() {
    _init
    _start
    _createdb_if_missing "$PGDATABASE"
    _createdb_if_missing "$PG_TEST_DATABASE"
}

case "${1:-ensure}" in
    ensure | start)
        _ensure
        ;;
    stop)
        if _is_running; then
            echo "Stopping local Postgres ..."
            pg_ctl -D "$PGDATA_DIR" stop -m fast >/dev/null
        fi
        ;;
    status)
        if _is_running; then
            echo "running on $PGHOST:$PGPORT"
        else
            echo "not running"
        fi
        ;;
    *)
        echo "Usage: $0 {ensure|start|stop|status}" >&2
        exit 1
        ;;
esac
