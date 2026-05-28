#!/usr/bin/env bash
# Removes the launchd LaunchAgent for the current project. No-op if not installed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
TARGET="$HOME/Library/LaunchAgents/com.user.claude-continue.$STATE_ID.plist"
LABEL="com.user.claude-continue.$STATE_ID"

if [ ! -f "$TARGET" ]; then
  echo "claude-continue: no launchd plist installed for $STATE_ID — nothing to do."
  exit 0
fi

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$TARGET"
echo "claude-continue: launchd plist removed for $STATE_ID."
