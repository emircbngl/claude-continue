---
name: rip
description: Total kill switch for claude-continue. Use when the user types "/rip", "/restinpeace", "stop awake", "kill the timer", or no longer wants auto-resume. Cancels the durable cron, uninstalls the launchd job (if any), snapshots state into archive/before-rip.md, clears the WARN marker, and flips awake_enabled to false so all hooks become no-ops. Reversible via /resurrect.
---

# `/rip` — kill switch

## Step 1 — Read state

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-state.sh" --quiet-if-missing
```

If no state exists, print "Nothing to rip — claude-continue is not active here." and stop.

## Step 2 — Confirm

`Are you sure? This cancels the cron and disables auto-resume. Reversible via /resurrect. (yes/no)`

## Step 3 — Snapshot to archive

```bash
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
STATE_ID=$(bash "$SCRIPT_DIR/state-path.sh")
STATE_DIR="$HOME/.claude/continue-state/$STATE_ID"
mkdir -p "$STATE_DIR/archive"
cp "$STATE_DIR/session.md" "$STATE_DIR/archive/before-rip.md"
```

## Step 4 — Cancel the cron

Call `CronList` and delete **every** job whose prompt contains `/awake-tick` via `CronDelete` — not just the one in `cron_job_id`. The chain may have created jobs the state file no longer tracks (each tick overwrites `cron_job_id` with the newest). Then also delete `cron_job_id` from state if it wasn't in the list.

## Step 5 — Uninstall launchd (if present)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-launchd.sh" || true
```

## Step 6 — Clear hook markers

```bash
rm -f "$HOME/.cache/claude-continue/warn-$STATE_ID"
```

This prevents `warn-emit.sh` from firing one last stale warning after rip.

## Step 7 — Flip state flags

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field awake_enabled false
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field status stopped
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_job_id ""
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_fires_at ""
```

## Step 8 — Confirm

> `claude-continue: ripped. cron cancelled, launchd removed, WARN cleared, state archived. /resurrect to bring back.`
