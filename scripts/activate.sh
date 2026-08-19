#!/usr/bin/env bash
# Pixi activation hook.
#
# Mojo's Python interop needs to dynamically load libpython. Its auto-discovery
# does not cope with spaces in the environment path (this project's directory
# has one), so we point it explicitly at the libpython that ships with the
# `mojo`/`mojo-python` conda packages inside this same pixi environment.
set -euo pipefail

if [ -n "${CONDA_PREFIX:-}" ]; then
    libpython="$(ls "${CONDA_PREFIX}"/lib/libpython3*.so 2>/dev/null | head -n 1)"
    if [ -n "${libpython}" ]; then
        export MOJO_PYTHON_LIBRARY="${libpython}"
    fi
fi

# Postgres connection defaults for the pixi-managed local instance (see
# scripts/pg_local.sh) -- only applied if not already set, so pointing at a
# different Postgres (a managed instance, someone else's local server) is
# just exporting these yourself before `pixi run ...`. db.mojo's connect()
# and pg_local.sh both read these, so they always agree on where the
# instance lives without duplicating the port/db names in two places.
export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5544}"
export PGDATABASE="${PGDATABASE:-products}"
export PGUSER="${PGUSER:-$(whoami)}"
export PG_TEST_DATABASE="${PG_TEST_DATABASE:-products_test}"
