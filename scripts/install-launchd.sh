#!/usr/bin/env bash
# Installs the launchd LaunchAgent for the current project. Opens the user's terminal of choice
# every ~5 hours and runs `claude -c "/awake"`.
# CLI-only — Desktop users don't need this. Skips with a message if CLAUDECODE is not set.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
TEMPLATE="$SCRIPT_DIR/com.user.claude-continue.plist.template"
TARGET="$HOME/Library/LaunchAgents/com.user.claude-continue.$STATE_ID.plist"
LABEL="com.user.claude-continue.$STATE_ID"

if [ "${CLAUDECODE:-0}" != "1" ] && [ ! -t 0 ]; then
  echo "claude-continue: Desktop or non-interactive environment detected. launchd installation skipped."
  echo "(Desktop users: CronCreate handles same-chat continuity; launchd is CLI-only.)"
  exit 0
fi

PROJECT_PATH="${1:-$PWD}"
TERM_APP="${TERM_PROGRAM:-Terminal}"

echo "claude-continue launchd installer"
echo "  state_id     : $STATE_ID"
echo "  project_path : $PROJECT_PATH"
echo "  detected term: $TERM_APP"
read -r -p "Terminal app to launch [$TERM_APP]? (Terminal/iTerm/Warp/Ghostty/<other>) " ans
[ -n "$ans" ] && TERM_APP="$ans"

[ -f "$TEMPLATE" ] || { echo "template missing: $TEMPLATE" >&2; exit 1; }

# Render template
sed -e "s|__STATE_ID__|$STATE_ID|g" \
    -e "s|__TERM_APP__|$TERM_APP|g" \
    -e "s|__PROJECT_PATH__|$PROJECT_PATH|g" \
    "$TEMPLATE" > "$TARGET"

# Load (bootstrap is idempotent-ish; bootout first if present)
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$TARGET"

echo "Installed → $TARGET"
echo "Verify: launchctl list | grep claude-continue"
