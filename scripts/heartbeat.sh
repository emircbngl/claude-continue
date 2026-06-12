#!/usr/bin/env bash
# Pure-shell heartbeat: refreshes usage snapshot, updates state.md, writes WARN marker if limit close.
# Called from PostToolUse hook. Zero Claude tokens.
# Throttle: 10-min minimum. last_updated bumps ONLY on successful usage refresh
# (a failed refresh must not lock out the retry; the 60-s negative cache in
# usage-detector.sh bounds the retry cost instead).
# All state mutations happen in ONE awk pass -> one tmp.$$ -> one mv (no fixed-name
# tmp races, no partial multi-pass states, frontmatter-only edits).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
STATE_DIR="$HOME/.claude/continue-state/$STATE_ID"
STATE_FILE="$STATE_DIR/session.md"
WARN_MARKER="$HOME/.cache/claude-continue/warn-$STATE_ID"

[ -f "$STATE_FILE" ] || exit 0
grep -q "^awake_enabled: true" "$STATE_FILE" || exit 0

NOW=$(date +%s)
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Throttle on last_updated (10 min); also skip entirely when the state is
# abandoned (>7 days) — no point refreshing usage for a dead task.
LAST=$(grep "^last_updated:" "$STATE_FILE" | sed 's/^last_updated: *//' | tr -d '"')
if [ -n "${LAST:-}" ]; then
  LAST_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$LAST" +%s 2>/dev/null \
         || date -u -d "$LAST" +%s 2>/dev/null || echo 0)
  AGE=$(( NOW - LAST_TS ))
  [ "$AGE" -lt 600 ] && exit 0
  [ "$LAST_TS" -gt 0 ] && [ "$AGE" -gt 604800 ] && exit 0
fi

USAGE=$("$SCRIPT_DIR/usage-detector.sh" 2>/dev/null || echo '{}')
command -v jq >/dev/null 2>&1 || exit 0
echo "$USAGE" | jq -e 'has("error") | not' >/dev/null 2>&1 || exit 0

REMAINING=$(echo "$USAGE" | jq -r '.remaining_min   // empty')
RESET_AT=$( echo "$USAGE" | jq -r '.reset_at        // empty')
COST=$(     echo "$USAGE" | jq -r '.cost_usd        // empty')
TPM=$(      echo "$USAGE" | jq -r '.tokens_per_min  // empty')
TOTAL=$(    echo "$USAGE" | jq -r '.total_tokens    // empty')
FETCHED=$(  echo "$USAGE" | jq -r '.fetched_at      // empty')

# Single-pass state update. Keys match with or without a value after the colon
# (index-based prefix check, no regex, no trailing-space requirement). Edits are
# confined to the frontmatter; a missing usage_snapshot block is seeded before
# the closing ---.
TMP="$STATE_FILE.tmp.$$"
HB_NOW="$NOW_ISO" HB_REMAINING="$REMAINING" HB_RESET="$RESET_AT" HB_COST="$COST" \
HB_TPM="$TPM" HB_TOTAL="$TOTAL" HB_FETCHED="$FETCHED" awk '
  function snapline(key, val) { return "  " key ": " val }
  function set(key, val, line) {
    if (val == "") return line
    return snapline(key, val)
  }
  BEGIN {
    in_fm = 0; seen_snap = 0
    vals["reset_at"]       = ENVIRON["HB_RESET"]
    vals["remaining_min"]  = ENVIRON["HB_REMAINING"]
    vals["tokens_per_min"] = ENVIRON["HB_TPM"]
    vals["total_tokens"]   = ENVIRON["HB_TOTAL"]
    vals["cost_usd"]       = ENVIRON["HB_COST"]
    vals["fetched_at"]     = ENVIRON["HB_FETCHED"]
    n = split("reset_at remaining_min tokens_per_min total_tokens cost_usd fetched_at", keys, " ")
  }
  /^---$/ {
    in_fm++
    if (in_fm == 2 && !seen_snap) {
      print "usage_snapshot:"
      for (i = 1; i <= n; i++) print snapline(keys[i], vals[keys[i]])
    }
    print; next
  }
  in_fm == 1 && index($0, "last_updated:") == 1 {
    print "last_updated: " ENVIRON["HB_NOW"]; next
  }
  in_fm == 1 && index($0, "usage_snapshot:") == 1 { seen_snap = 1; print; next }
  in_fm == 1 && seen_snap {
    for (i = 1; i <= n; i++) {
      k = keys[i]
      if (index($0, "  " k ":") == 1) {
        if (vals[k] != "") print snapline(k, vals[k]); else print
        next
      }
    }
    print; next
  }
  { print }
' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE" || rm -f "$TMP"

# WARN trigger: remaining < 30 min, throttled to once per 30 min
if [ -n "${REMAINING:-}" ] && [ "$REMAINING" -lt 30 ] 2>/dev/null; then
  WARN_AGE=99999
  if [ -f "$WARN_MARKER" ]; then
    M=$(stat -f %m "$WARN_MARKER" 2>/dev/null || stat -c %Y "$WARN_MARKER" 2>/dev/null || echo 0)
    WARN_AGE=$(( NOW - M ))
  fi
  if [ "$WARN_AGE" -gt 1800 ]; then
    mkdir -p "$(dirname "$WARN_MARKER")"
    printf '%s\n' "$REMAINING" > "$WARN_MARKER"
  fi
fi

exit 0
