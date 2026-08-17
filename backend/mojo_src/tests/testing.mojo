# Minimal native-Mojo test helper.
#
# Mojo v1.0 GA has no built-in test framework (`mojo test` doesn't exist),
# so this project uses a small convention instead: each test file is a
# plain Mojo script with a `main()` that calls `check(...)` for every
# assertion and prints one PASS/FAIL line per check. An unmet check raises,
# which makes `mojo run` exit non-zero -- enough to wire into `pixi run test`
# and CI without needing a real test runner.


def check(condition: Bool, description: String) raises:
    if condition:
        print("PASS:", description)
    else:
        raise Error("FAIL: " + description)
