---
name: resurrect
description: Reverse a /rip — re-enable claude-continue. Use when the user types "/resurrect", "undo rip", "bring it back", or wants to re-enable auto-resume after stopping. Flips awake_enabled back on in the LIVE state file (preserving any /save-state work done after the rip), re-schedules the cron, and optionally re-installs launchd. Falls back to archive/before-rip.md only if the live state is gone.
---

# `/resurrect` — undo /rip

## Step 1 — Locate state

```bash
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
STATE_ID=$(bash "$SCRIPT_DIR/state-path.sh")
STATE_DIR="$HOME/.claude/continue-state/$STATE_ID"
STATE_FILE="$STATE_DIR/session.md"
SNAPSHOT="$STATE_DIR/archive/before-rip.md"
```

## Step 2 — Re-enable (flag flip, NOT wholesale restore)

`/rip` only flips flags — the live `session.md` still holds everything saved since, including post-rip `/save-state` snapshots. So the default path just flips them back:

- If `$STATE_FILE` exists:

```bash
bash "$SCRIPT_DIR/write-state.sh" --field awake_enabled true
bash "$SCRIPT_DIR/write-state.sh" --field status in-progress
```

- If `$STATE_FILE` is **missing** but `$SNAPSHOT` exists (disaster recovery — someone deleted the live state):

```bash
cp "$SNAPSHOT" "$STATE_FILE"
bash "$SCRIPT_DIR/write-state.sh" --field awake_enabled true
bash "$SCRIPT_DIR/write-state.sh" --field status in-progress
```

- If neither exists → nothing to resurrect; treat this as a fresh `/awake` instead.

## Step 3 — Re-schedule cron

```bash
RESET_AT=$(bash "$SCRIPT_DIR/usage-detector.sh" | jq -r '.reset_at // empty')
bash "$SCRIPT_DIR/next-cron.sh" "$RESET_AT"
```

`next-cron.sh` handles a null/stale `reset_at` (common after days of no usage post-rip) with its built-in now+5h05m fallback. Call `CronCreate(cron: "<CRON_EXPR>", prompt: "/awake-tick", durable: true, recurring: false)`, then write the new `cron_job_id` and `cron_fires_at` into state — this also overwrites any stale pre-rip cron fields.

## Step 4 — Ask about launchd

If `~/Library/LaunchAgents/com.user.claude-continue.${STATE_ID}.plist` previously existed, ask: `Re-install the launchd auto-launch job? (yes/no)`. If yes, run `install-launchd.sh`.

## Step 5 — Confirm

Print one line: `claude-continue: resurrected. cron armed for <local time>. Welcome back.`
