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

Call `CronList` and delete **every** job whose prompt contains `/awake-tick` via `CronDelete`. Then ALWAYS also call `CronDelete` with the state's `cron_job_id` even if CronList showed nothing — `CronList` is session-scoped, so a durable cron armed in a *previous* session is invisible to it; a "not found" error is expected and fine.

**Know what actually kills the chain:** cron deletion is best-effort cleanup. The authoritative kill is `awake_enabled: false` (Step 7) — any orphan durable cron that survives will fire `/awake-tick` once, hit that guard, and die without re-chaining. Tell the user this if they ask whether something might still fire: one silent no-op fire is possible, a continuing chain is not.

## Step 5 — Uninstall launchd (if present)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-launchd.sh" || true
ls "$HOME/Library/LaunchAgents/com.user.claude-continue."*.plist 2>/dev/null
```

If the `ls` shows agents for OTHER projects, tell the user and ask whether to remove those too: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-launchd.sh" --all`. (/rip is per-project by default; "total" means this project's cron, launchd, hooks.)

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
