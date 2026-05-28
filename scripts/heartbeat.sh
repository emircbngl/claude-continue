#!/usr/bin/env bash
# Pure-shell heartbeat: refreshes usage snapshot, updates state.md, writes WARN marker if limit close.
# Called from PostToolUse hook. Zero Claude tokens.
# Throttle: 10-min minimum between updates. last_updated is bumped ONLY if usage refresh succeeded
# (otherwise the throttle would lock out recovery).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
STATE_DIR="$HOME/.claude/continue-state/$STATE_ID"
STATE_FILE="$STATE_DIR/session.md"

# Guards
[ -f "$STATE_FILE" ] || exit 0
grep -q "^awake_enabled: true" "$STATE_FILE" || exit 0

NOW=$(date +%s)
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Throttle check (10 min)
LAST=$(grep "^last_updated:" "$STATE_FILE" | sed 's/^last_updated: *//' | tr -d '"')
if [ -n "${LAST:-}" ]; then
  LAST_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$LAST" +%s 2>/dev/null \
         || date -u -d "$LAST" +%s 2>/dev/null || echo 0)
  AGE=$(( NOW - LAST_TS ))
  [ "$AGE" -lt 600 ] && exit 0
fi

# Ensure usage_snapshot block exists (idempotent — only adds if missing)
if ! grep -q "^usage_snapshot:" "$STATE_FILE"; then
  awk '
    /^---$/ {
      c++
      if (c == 2) {
        print "usage_snapshot:"
        print "  reset_at: "
        print "  remaining_min: "
        print "  tokens_per_min: "
        print "  total_tokens: "
        print "  cost_usd: "
        print "  fetched_at: "
      }
    }
    { print }
  ' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
fi

# Refresh usage
USAGE=$("$SCRIPT_DIR/usage-detector.sh" 2>/dev/null || echo '{}')
USAGE_OK=0
if command -v jq >/dev/null 2>&1; then
  if echo "$USAGE" | jq -e 'has("error") | not' >/dev/null 2>&1; then
    USAGE_OK=1
    REMAINING=$(echo "$USAGE" | jq -r '.remaining_min   // empty')
    RESET_AT=$( echo "$USAGE" | jq -r '.reset_at        // empty')
    COST=$(     echo "$USAGE" | jq -r '.cost_usd        // empty')
    TPM=$(      echo "$USAGE" | jq -r '.tokens_per_min  // empty')
    TOTAL=$(    echo "$USAGE" | jq -r '.total_tokens    // empty')
    FETCHED=$(  echo "$USAGE" | jq -r '.fetched_at      // empty')

    # awk-based field updater — handles both indented and top-level keys, safely escapes via -v
    upd() {
      local key="$1" val="$2"
      [ -n "${val:-}" ] || return 0
      awk -v k="$key" -v v="$val" '
        { line = $0 }
        match(line, "^  "k": ") { print "  " k ": " v; next }
        match(line, "^"k": ")   { print k ": " v;       next }
        { print line }
      ' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    }
    upd remaining_min  "$REMAINING"
    upd reset_at       "$RESET_AT"
    upd cost_usd       "$COST"
    upd tokens_per_min "$TPM"
    upd total_tokens   "$TOTAL"
    upd fetched_at     "$FETCHED"
  fi
fi

# Bump last_updated ONLY if usage refresh succeeded (don't lock out recovery)
if [ "$USAGE_OK" = "1" ]; then
  awk -v ts="$NOW_ISO" '
    /^last_updated:/ { print "last_updated: " ts; next }
    { print }
  ' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

  # WARN trigger
  WARN_MARKER="/tmp/claude-continue-warn-$STATE_ID"
  if [ -n "${REMAINING:-}" ] && [ "$REMAINING" -lt 30 ] 2>/dev/null; then
    WARN_AGE=99999
    if [ -f "$WARN_MARKER" ]; then
      M=$(stat -f %m "$WARN_MARKER" 2>/dev/null || stat -c %Y "$WARN_MARKER" 2>/dev/null || echo 0)
      WARN_AGE=$(( NOW - M ))
    fi
    if [ "$WARN_AGE" -gt 1800 ]; then
      printf '%s\n' "$REMAINING" > "$WARN_MARKER"
    fi
  fi
fi

exit 0
