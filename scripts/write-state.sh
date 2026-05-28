#!/usr/bin/env bash
# Atomically writes state.md from stdin (or --field KEY VALUE for single-field update).
# Archives previous version under archive/<ISO>.md before overwriting (full-write only).
# --field supports both top-level and indented (2-space) nested keys; inserts as top-level if missing.
# Values are passed via awk -v (NOT shell interpolation) so sed-metacharacters are safe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
STATE_DIR="$HOME/.claude/continue-state/$STATE_ID"
STATE_FILE="$STATE_DIR/session.md"
ARCHIVE_DIR="$STATE_DIR/archive"

mkdir -p "$STATE_DIR" "$ARCHIVE_DIR"

if [ "${1:-}" = "--field" ]; then
  KEY="$2"; VAL="${3:-}"
  [ -f "$STATE_FILE" ] || { echo "state file missing; use full-write first" >&2; exit 1; }

  awk -v k="$KEY" -v v="$VAL" '
    BEGIN { replaced = 0; in_fm = 0; fm_end_line = 0 }
    /^---$/ { in_fm++ }
    in_fm == 1 && match($0, "^  "k": ") { print "  " k ": " v; replaced = 1; next }
    in_fm == 1 && match($0, "^"k": ")   { print k ": " v;       replaced = 1; next }
    in_fm == 2 && fm_end_line == 0 && !replaced { print k ": " v; fm_end_line = 1 }
    { print }
  ' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  echo "$STATE_FILE"
  exit 0
fi

if [ -f "$STATE_FILE" ]; then
  ISO=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
  cp "$STATE_FILE" "$ARCHIVE_DIR/$ISO.md"
fi

TMP="$STATE_FILE.tmp.$$"
cat > "$TMP"
mv "$TMP" "$STATE_FILE"
echo "$STATE_FILE"
