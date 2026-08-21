## Purpose

Automatically catch a broken test or a failed frontend build on every push
and pull request, and let a developer run the identical checks on their own
machine before pushing.

## ADDED Requirements

### Requirement: Automated checks run on every push and pull request
The system SHALL run the native-Mojo test suite, the frontend lint, and the
frontend build automatically on every push to `main` and on every pull
request targeting `main`, without requiring a person to trigger it
manually.

#### Scenario: Pull request opened
- **WHEN** a pull request is opened or updated against `main`
- **THEN** the test suite and frontend build SHALL run automatically and
  report a pass/fail result on the pull request

#### Scenario: Push to main
- **WHEN** a commit is pushed directly to `main`
- **THEN** the test suite and frontend build SHALL run automatically

#### Scenario: A test fails
- **WHEN** any native-Mojo test in the suite fails
- **THEN** the overall check SHALL be reported as failed, and the failing
  test's output SHALL be visible in the check's log

### Requirement: Pull requests are gated on checks passing
The system SHALL prevent a pull request against `main` from being merged
while its automated checks are failing or have not yet completed.

#### Scenario: Merge blocked on failing checks
- **WHEN** a pull request's automated checks have failed
- **THEN** the pull request SHALL be blocked from merging until the checks
  pass (or are re-run and pass)

### Requirement: The same checks are runnable locally
The system SHALL provide a single local command that runs the exact same
checks the automated remote workflow runs, so a developer can validate
their changes before pushing.

#### Scenario: Developer runs checks before pushing
- **WHEN** a developer runs the local check command on their machine
- **THEN** it SHALL run the same test suite and frontend build the remote
  workflow runs, and SHALL fail (non-zero exit) if either fails

#### Scenario: Local and remote checks agree
- **WHEN** the local check command passes on a developer's machine
- **THEN** the remote workflow SHALL also pass for that same commit, absent
  environment differences outside the project's control
