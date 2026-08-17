#!/usr/bin/env bash
# Runs every native-Mojo test file under backend/mojo_src/tests/.
# See backend/mojo_src/tests/testing.mojo for why this shell loop exists
# instead of a real test runner (Mojo v1.0 GA has no `mojo test`).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
for test_file in backend/mojo_src/tests/test_*.mojo; do
    echo "=== $test_file ==="
    if ! mojo run -I backend/mojo_src "$test_file"; then
        status=1
    fi
    echo
done

exit $status
