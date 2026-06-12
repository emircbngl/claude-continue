#!/usr/bin/env bash
# Reads the state file and prints to stdout.
# Usage: read-state.sh [--quiet-if-missing] [--hook]
#   --quiet-if-missing : print nothing (instead of NO_STATE) when no state exists
#   --hook             : SessionStart-hook mode — stay SILENT unless awake_enabled
#                        is true (token-leak guard: an inactive project must not
#                        push its state into every session's context). Also
#                        emits a CRON_EXPIRED line if cron_fires_at has passed,
#                        so Claude can suggest re-arming via /awake.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"

QUIET=0; HOOK=0
for arg in "$@"; do
  case "$arg" in
    --quiet-if-missing) QUIET=1 ;;
    --hook) HOOK=1; QUIET=1 ;;
  esac
done

if [ ! -f "$STATE_FILE" ]; then
  [ "$QUIET" -eq 0 ] && echo "NO_STATE"
  exit 0
fi

if [ "$HOOK" -eq 1 ]; then
  grep -q "^awake_enabled: true" "$STATE_FILE" || exit 0
fi

printf '=== claude-continue state (%s) ===\n' "$STATE_ID"
cat "$STATE_FILE"

if [ "$HOOK" -eq 1 ]; then
  FIRES=$(grep "^cron_fires_at:" "$STATE_FILE" | sed 's/^cron_fires_at: *//' | tr -d '" ')
  if [ -n "${FIRES:-}" ]; then
    FIRES_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$FIRES" +%s 2>/dev/null \
            || date -u -d "$FIRES" +%s 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ "$FIRES_TS" -gt 0 ] && [ "$NOW" -gt $(( FIRES_TS + 600 )) ]; then
      echo "CRON_EXPIRED: scheduled fire time $FIRES has passed without a tick (CLI closed >grace, or the 7-day durable-cron expiry hit). Suggest the user run /awake to re-arm."
    fi
  fi
fi
