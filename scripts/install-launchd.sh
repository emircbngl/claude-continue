#!/usr/bin/env bash
# Installs the launchd LaunchAgent for the current project. Opens the user's terminal of choice
# every ~5 hours and runs `claude -c "/awake"` with CLAUDE_CONTINUE_UNATTENDED=1.
# CLI-only — Desktop users don't need this (CronCreate covers continuity in-app).
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
case "$TERM_APP" in
  Apple_Terminal) TERM_APP="Terminal" ;;
  iTerm.app)      TERM_APP="iTerm" ;;
esac

echo "claude-continue launchd installer"
echo "  state_id     : $STATE_ID"
echo "  project_path : $PROJECT_PATH"
echo "  detected term: $TERM_APP"
if [ -t 0 ]; then
  read -r -p "Terminal app to launch [$TERM_APP]? (Terminal/iTerm/Warp/Ghostty/<other>) " ans || ans=""
  [ -n "$ans" ] && TERM_APP="$ans"
else
  echo "  (non-interactive: using $TERM_APP)"
fi

if [ "$TERM_APP" != "Terminal" ]; then
  echo "  NOTE: the AppleScript 'do script' verb is Terminal.app syntax. iTerm/Warp/Ghostty"
  echo "  may need a different verb — if the window opens but no command runs, see README."
fi

[ -f "$TEMPLATE" ] || { echo "template missing: $TEMPLATE" >&2; exit 1; }

# Escape sed replacement metacharacters (&, \, and the | delimiter) in user-controlled values
sed_escape() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
ESC_STATE_ID=$(sed_escape "$STATE_ID")
ESC_TERM_APP=$(sed_escape "$TERM_APP")
ESC_PROJECT_PATH=$(sed_escape "$PROJECT_PATH")

sed -e "s|__STATE_ID__|$ESC_STATE_ID|g" \
    -e "s|__TERM_APP__|$ESC_TERM_APP|g" \
    -e "s|__PROJECT_PATH__|$ESC_PROJECT_PATH|g" \
    "$TEMPLATE" > "$TARGET"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$TARGET"

echo "Installed → $TARGET"
echo "Verify: launchctl list | grep claude-continue"
echo "Note: StartInterval counts from load time, not from the usage-window boundary;"
echo "the in-session durable cron remains the precise mechanism."
