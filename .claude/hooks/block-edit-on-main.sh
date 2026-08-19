#!/usr/bin/env bash
# PreToolUse hook (Write|Edit|NotebookEdit): blocks code edits landing
# directly on the repo's default branch (main). openspec/ planning files
# are exempt (proposals/specs/tasks are fine to write on main). Ignored
# paths (dist/, node_modules/, data/pgdata/, etc.) are also exempt since
# they aren't source.
set -euo pipefail

input="$(cat)"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -z "$f" ] && exit 0

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$root" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch="$(git branch --show-current 2>/dev/null || true)"
[ "$branch" = "main" ] || exit 0

root="$(git rev-parse --show-toplevel)"
case "$f" in
  /*) abs="$f" ;;
  *) abs="$root/$f" ;;
esac

case "$abs" in
  "$root"/openspec/*) exit 0 ;;
  "$root"/*) rel="${abs#"$root"/}" ;;
  *) exit 0 ;; # outside this repo entirely -- not our concern
esac

git check-ignore -q "$rel" 2>/dev/null && exit 0

reason="Blocked: you're on main (the default branch). Create/switch to a feature branch before editing $rel -- e.g. git checkout -b feat/<name> -- then retry."
jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
