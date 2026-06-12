#!/usr/bin/env bash
# Invoked by UserPromptSubmit hook — i.e. on every REAL user prompt. Two jobs:
# 1. Reset the ticks_unattended dead-man counter (a human is present; ticks may chain again).
# 2. If a WARN marker exists AND awake_enabled is true, emit one line and delete the marker.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
WARN_MARKER="$HOME/.cache/claude-continue/warn-$STATE_ID"
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"

# Dead-man reset: only write when the counter is present and nonzero (no-op on normal prompts)
if [ -f "$STATE_FILE" ] && grep -q "^ticks_unattended: [1-9]" "$STATE_FILE"; then
  "$SCRIPT_DIR/write-state.sh" --field ticks_unattended 0 >/dev/null 2>&1 || true
fi

[ -f "$WARN_MARKER" ] || exit 0

if [ ! -f "$STATE_FILE" ] || ! grep -q "^awake_enabled: true" "$STATE_FILE"; then
  rm -f "$WARN_MARKER"
  exit 0
fi

REMAINING=$(cat "$WARN_MARKER" 2>/dev/null || echo "?")
LAST=$(grep "^last_updated:" "$STATE_FILE" 2>/dev/null | sed 's/^last_updated: *//' | tr -d '"' || echo "?")

printf '[claude-continue] %s dk kaldı (5h pencere) — son save: %s. /save-state ile manuel snapshot alabilirsin.\n' "$REMAINING" "$LAST"
rm -f "$WARN_MARKER"