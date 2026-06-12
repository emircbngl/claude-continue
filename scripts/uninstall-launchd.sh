#!/usr/bin/env bash
# Removes the launchd LaunchAgent(s).
# Default: current project only. --all: every com.user.claude-continue.* agent
# (covers orphans whose project was renamed/moved/deleted, since their state-ids
# no longer resolve from any cwd).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/.cache/claude-continue"

remove_one() { # remove_one PLIST_PATH
  local plist="$1" label
  label=$(basename "$plist" .plist)
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$plist"
  local sid="${label#com.user.claude-continue.}"
  rm -f "$LOG_DIR/$sid.out" "$LOG_DIR/$sid.err" "$LOG_DIR/launchd-fire-$sid.sh"
  echo "removed: $label"
}

if [ "${1:-}" = "--all" ]; then
  found=0
  for plist in "$HOME/Library/LaunchAgents/com.user.claude-continue."*.plist; do
    [ -f "$plist" ] || continue
    remove_one "$plist"
    found=1
  done
  [ "$found" -eq 0 ] && echo "claude-continue: no launchd agents installed."
  exit 0
fi

STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
TARGET="$HOME/Library/LaunchAgents/com.user.claude-continue.$STATE_ID.plist"

if [ ! -f "$TARGET" ]; then
  echo "claude-continue: no launchd plist installed for $STATE_ID — nothing to do."
  others=$(ls "$HOME/Library/LaunchAgents/com.user.claude-continue."*.plist 2>/dev/null | wc -l | tr -d ' ')
  [ "${others:-0}" -gt 0 ] && echo "Note: $others agent(s) exist for OTHER projects — remove all with: $0 --all"
  exit 0
fi

remove_one "$TARGET"