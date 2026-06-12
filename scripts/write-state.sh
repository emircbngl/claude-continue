#!/usr/bin/env bash
# Atomically writes state.md from stdin (or --field KEY VALUE for single-field update).
# Full-write: archives the previous version, rejects empty stdin (state-destruction guard).
# --field: updates a top-level or 2-space-indented frontmatter key, inserting top-level if
# missing; only operates INSIDE the frontmatter block; exits 1 if nothing was changed.
# Values reach awk via ENVIRON (no -v) so backslashes survive untouched.
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

  TMP="$STATE_FILE.tmp.$$"
  WS_KEY="$KEY" WS_VAL="$VAL" awk '
    BEGIN {
      k = ENVIRON["WS_KEY"]; v = ENVIRON["WS_VAL"]
      replaced = 0; inserted = 0; in_fm = 0
    }
    /^---$/ {
      in_fm++
      if (in_fm == 2 && !replaced) { print k ": " v; inserted = 1 }
      print; next
    }
    in_fm == 1 && (index($0, "  " k ":") == 1 || index($0, k ":") == 1) {
      prefix = (index($0, "  ") == 1) ? "  " : ""
      print prefix k ": " v
      replaced = 1; next
    }
    { print }
    END { exit (replaced || inserted) ? 0 : 1 }
  ' "$STATE_FILE" > "$TMP" || { rm -f "$TMP"; echo "field update failed: $KEY" >&2; exit 1; }
  mv "$TMP" "$STATE_FILE"
  echo "$STATE_FILE"
  exit 0
fi

# Full write — buffer stdin first and refuse to clobber state with empty input
TMP="$STATE_FILE.tmp.$$"
cat > "$TMP"
if [ ! -s "$TMP" ]; then
  rm -f "$TMP"
  echo "refusing to write empty state (stdin was empty)" >&2
  exit 1
fi

if [ -f "$STATE_FILE" ]; then
  ISO=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
  cp "$STATE_FILE" "$ARCHIVE_DIR/$ISO.md"
fi

mv "$TMP" "$STATE_FILE"
echo "$STATE_FILE"
