#!/usr/bin/env bash
# Installs the launchd LaunchAgent for the current project. The agent NEVER opens a
# window: every fire runs launchd-fire.sh, a pure-shell guard that self-uninstalls
# when the plugin/task is gone, skips when state is stale or a claude is already
# running, and otherwise launches claude HEADLESSLY (claude -c -p) so the queued
# durable cron can fire. Niche opt-in — the core plugin needs none of this.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_ID="$("$SCRIPT_DIR/state-path.sh")"
TEMPLATE="$SCRIPT_DIR/com.user.claude-continue.plist.template"
TARGET="$HOME/Library/LaunchAgents/com.user.claude-continue.$STATE_ID.plist"
LABEL="com.user.claude-continue.$STATE_ID"
LOG_DIR="$HOME/.cache/claude-continue"
FIRE_SRC="$SCRIPT_DIR/launchd-fire.sh"
FIRE_DST="$LOG_DIR/launchd-fire-$STATE_ID.sh"

if [ "${CLAUDECODE:-0}" != "1" ] && [ ! -t 0 ]; then
  echo "claude-continue: Desktop or non-interactive environment detected. launchd installation skipped."
  echo "(The durable cron re-activates the existing chat in place; launchd is a niche CLI extra.)"
  exit 0
fi

PROJECT_PATH="${1:-$PWD}"
mkdir -p "$LOG_DIR"

echo "claude-continue launchd installer (headless — no windows will be opened)"
echo "  state_id     : $STATE_ID"
echo "  project_path : $PROJECT_PATH"

[ -f "$TEMPLATE" ] || { echo "template missing: $TEMPLATE" >&2; exit 1; }
[ -f "$FIRE_SRC" ] || { echo "launchd-fire.sh missing: $FIRE_SRC" >&2; exit 1; }

# Escape sed replacement metacharacters in user-controlled values
sed_escape() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
ESC_STATE_ID=$(sed_escape "$STATE_ID")
ESC_PROJECT_PATH=$(sed_escape "$PROJECT_PATH")
ESC_PLUGIN_ROOT=$(sed_escape "$PLUGIN_ROOT")
ESC_LOG_DIR=$(sed_escape "$LOG_DIR")
ESC_FIRE_DST=$(sed_escape "$FIRE_DST")

# Render the fire script OUTSIDE the plugin dir (it must survive long enough to
# self-uninstall the agent even after `claude plugin uninstall` removes the plugin)
sed -e "s|__PLUGIN_ROOT__|$ESC_PLUGIN_ROOT|g" \
    -e "s|__PROJECT_PATH__|$ESC_PROJECT_PATH|g" \
    -e "s|__STATE_ID__|$ESC_STATE_ID|g" \
    "$FIRE_SRC" > "$FIRE_DST"
chmod +x "$FIRE_DST"

sed -e "s|__STATE_ID__|$ESC_STATE_ID|g" \
    -e "s|__LAUNCHD_FIRE__|$ESC_FIRE_DST|g" \
    -e "s|__LOG_DIR__|$ESC_LOG_DIR|g" \
    "$TEMPLATE" > "$TARGET"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$TARGET"

echo "Installed → $TARGET"
echo "Fire guard → $FIRE_DST"
echo "Verify: launchctl list | grep claude-continue"
echo "Behavior: headless 'claude -c -p' only when state is live (<24h activity),"
echo "no other claude is running, and the task is not done/ripped. Self-uninstalls"
echo "when the plugin, project, or state disappears."