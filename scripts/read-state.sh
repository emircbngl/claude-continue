#!/usr/bin/env bash
# Reads the state file and prints to stdout.
# Usage: read-state.sh [--quiet-if-missing]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"

QUIET=0
[ "${1:-}" = "--quiet-if-missing" ] && QUIET=1

if [ -f "$STATE_FILE" ]; then
  printf '=== claude-continue state (%s) ===\n' "$STATE_ID"
  cat "$STATE_FILE"
elif [ "$QUIET" -eq 0 ]; then
  echo "NO_STATE"
fi
