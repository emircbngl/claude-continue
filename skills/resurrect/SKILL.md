---
name: resurrect
description: Reverse a /rip — restore claude-continue from the pre-rip archive snapshot. Use when the user types "/resurrect", "undo rip", "bring it back", or wants to re-enable auto-resume after stopping. Restores state from archive/before-rip.md, sets awake_enabled true, optionally re-schedules the cron and re-installs launchd.
---

# `/resurrect` — undo /rip

## Step 1 — Locate the snapshot

```bash
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
STATE_ID=$(bash "$SCRIPT_DIR/state-path.sh")
STATE_DIR="$HOME/.claude/continue-state/$STATE_ID"
SNAPSHOT="$STATE_DIR/archive/before-rip.md"
```

If `$SNAPSHOT` is missing → no rip to undo; instead, treat this as `/awake` for a fresh session.

## Step 2 — Restore

```bash
cp "$SNAPSHOT" "$STATE_DIR/session.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field awake_enabled true
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field status in-progress
```

## Step 3 — Re-schedule cron

Run `usage-detector.sh`, compute `reset_at + 5min`, call `CronCreate` with `durable: true, recurring: false, prompt: "/awake-tick"`. Write the new `cron_job_id` and `cron_fires_at` into state.

## Step 4 — Ask about launchd

If the launchd plist was previously installed (check `~/Library/LaunchAgents/com.user.claude-continue.${STATE_ID}.plist`), ask the user: `Re-install the launchd auto-launch job? (yes/no)`. If yes, run `install-launchd.sh`.

## Step 5 — Confirm

Print one line: `claude-continue: resurrected. cron armed for <local time>. Welcome back.`
