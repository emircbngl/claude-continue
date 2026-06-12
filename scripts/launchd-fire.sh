#!/usr/bin/env bash
# Invoked by the launchd LaunchAgent every StartInterval. NEVER opens a window.
# Decides, in pure shell, whether launching claude headlessly is warranted —
# and self-uninstalls when the plugin/task is gone so the agent cannot outlive
# its purpose. Substituted at install time: __PLUGIN_ROOT__, __PROJECT_PATH__,
# __STATE_ID__.
set -uo pipefail

PLUGIN_ROOT="__PLUGIN_ROOT__"
PROJECT_PATH="__PROJECT_PATH__"
STATE_ID="__STATE_ID__"
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"
PLIST="$HOME/Library/LaunchAgents/com.user.claude-continue.$STATE_ID.plist"
LABEL="com.user.claude-continue.$STATE_ID"

self_uninstall() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  exit 0
}

# 1. Plugin or project gone (uninstalled / moved / deleted) → agent must not outlive them
[ -d "$PLUGIN_ROOT" ] || self_uninstall
[ -d "$PROJECT_PATH" ] || self_uninstall

# 2. Task finished or ripped → tear down without ever launching claude
[ -f "$STATE_FILE" ] || self_uninstall
grep -q "^awake_enabled: true" "$STATE_FILE" || self_uninstall
grep -q "^status: done" "$STATE_FILE" && self_uninstall

# 3. State stale (no heartbeat in >24h: nobody is working on this) → skip, don't burn a launch
LAST=$(grep "^last_updated:" "$STATE_FILE" | sed 's/^last_updated: *//' | tr -d '"')
if [ -n "${LAST:-}" ]; then
  LAST_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$LAST" +%s 2>/dev/null \
         || date -u -d "$LAST" +%s 2>/dev/null || echo 0)
  if [ "$LAST_TS" -gt 0 ] && [ $(( $(date +%s) - LAST_TS )) -gt 86400 ]; then
    exit 0
  fi
fi

# 4. A claude is already running → it will process the queued cron itself; do nothing
pgrep -f "claude" >/dev/null 2>&1 && exit 0

# 5. Headless launch: no window, no REPL. Resumes the most recent conversation in the
#    project; the queued durable cron fires during this launch; /awake's UNATTENDED
#    path defers decisions; the process exits when the turn completes.
cd "$PROJECT_PATH" || exit 0
CLAUDE_CONTINUE_UNATTENDED=1 claude -c -p "/awake" >/dev/null 2>&1 || true
exit 0
