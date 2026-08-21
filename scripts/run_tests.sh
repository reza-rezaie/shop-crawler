#!/usr/bin/env bash
# Runs every native-Mojo test file under backend/src/tests/.
# See backend/src/tests/testing.mojo for why this shell loop exists
# instead of a real test runner (Mojo v1.0 GA has no `mojo test`).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
while IFS= read -r -d '' test_file; do
    echo "=== $test_file ==="
    if ! mojo run -I backend/src "$test_file"; then
        status=1
    fi
    echo
done < <(find backend/src/tests -name 'test_*.mojo' -print0 | sort -z)

exit $status
