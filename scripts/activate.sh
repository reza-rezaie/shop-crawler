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
