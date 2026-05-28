#!/usr/bin/env bash
# Invoked by UserPromptSubmit hook. If a WARN marker exists AND awake_enabled is true,
# emits one line to stdout (Claude sees as context), then deletes the marker.
# After /rip we delete the marker proactively so this is doubly safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
WARN_MARKER="/tmp/claude-continue-warn-$STATE_ID"
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"

[ -f "$WARN_MARKER" ] || exit 0

# If state is gone or awake is disabled, silently clear the stale marker
if [ ! -f "$STATE_FILE" ] || ! grep -q "^awake_enabled: true" "$STATE_FILE"; then
  rm -f "$WARN_MARKER"
  exit 0
fi

REMAINING=$(cat "$WARN_MARKER" 2>/dev/null || echo "?")
LAST=$(grep "^last_updated:" "$STATE_FILE" 2>/dev/null | sed 's/^last_updated: *//' | tr -d '"' || echo "?")

printf '[claude-continue] %s dk kaldı (5h pencere) — son save: %s. /save-state ile manuel snapshot alabilirsin.\n' "$REMAINING" "$LAST"
rm -f "$WARN_MARKER"
