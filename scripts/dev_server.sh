#!/usr/bin/env bash
# Convenience launcher for local dev: builds the frontend if it hasn't been
# built yet, starts the backend on a fixed, deliberately unusual port (so it
# doesn't collide with whatever else you've got running on 3000/5000/8000/
# 8080/etc.), and prints the URL to open. Run via `pixi run dev` (like the
# other tasks in pixi.toml) so Mojo's Python interop is set up correctly --
# see scripts/activate.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PORT="${PORT:-8934}"

# Fail fast with a clear message instead of a raw "address already in use"
# traceback if something else is already listening on this port.
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    exec 3>&-
    echo "Port $PORT is already in use." >&2
    echo "Pick a different one: PORT=8935 pixi run dev" >&2
    exit 1
fi

if [ ! -f frontend/dist/index.html ]; then
    echo "No frontend build found -- building it first (one-time, or after frontend changes)..."
    if [ ! -d frontend/node_modules ]; then
        npm install --prefix frontend
    fi
    npm run build --prefix frontend
    echo
fi

echo "Starting Mojo Product Crawler..."
echo
echo "  👉  http://localhost:$PORT"
echo
echo "(Ctrl+C to stop)"
echo

python backend/server.py --port "$PORT"
