---
name: awake-tick
description: This skill should be used when the user types "/awake-tick" or "awake tick", or when a prompt contains "claude-continue cron fired" or "follow the awake-tick skill" (the plain-text prompt the claude-continue cron enqueues after a 5-hour usage window). Ultra-minimal — does NOT summarize and does NOT ask the user questions. Confirms the scheduled fire time has arrived, prints a single-line resumed message, and chains the next cron — unless the dead-man switch says nobody is around.
---

# `/awake-tick` — cron-fired resumer (ultra-minimal)

Invoked by the durable cron created by `/awake`. The user typically did not just type anything; they may not be at the terminal. Keep tool calls and output tight.

## Step 1 — Read state

```bash
STATE_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-path.sh")
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-state.sh" --quiet-if-missing
```

## Step 2 — Halt checks (in this order)

1. **State missing or `awake_enabled: false`** → silent exit. (This guard is the authoritative chain-killer: even an orphan durable cron from an old session dies here without re-chaining.)
2. **`status: done`** → the task finished but cleanup never ran. Do it now, then exit:
   - `CronDelete` the state's `cron_job_id` (a "not found" error is fine).
   - `write-state.sh --field awake_enabled false`, `--field cron_job_id ""`, `--field cron_fires_at ""`.
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-launchd.sh"` (no-op if not installed).
   - Print one line: `claude-continue: task done — auto-wake torn down.`
3. **Dead-man switch**: read `ticks_unattended` from the frontmatter. If it is **2 or more**, the user has not typed a single prompt across two whole windows — stop forcing wake-ups:
   - `write-state.sh --field cron_job_id ""` and `--field cron_fires_at ""` (so the SessionStart hook stops nagging CRON_EXPIRED).
   - Print one line: `claude-continue: 2 pencere boyunca kullanıcı aktivitesi yok — auto-wake duraklatıldı. /awake ile yeniden kur.`
   - Exit. Do NOT chain.
   (The counter is reset to 0 by the UserPromptSubmit hook the moment the user types anything — an active user never hits this.)
4. **Early fire**: compare the state's own `cron_fires_at` with now:

```bash
FIRES=$(grep "^cron_fires_at:" "$STATE_FILE" | sed 's/^cron_fires_at: *//' | tr -d '" ')
FIRES_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$FIRES" +%s 2>/dev/null \
        || date -u -d "$FIRES" +%s 2>/dev/null || echo 0)
NOW=$(date +%s)
```

   If `NOW < FIRES_TS` → a cron for that time is still armed; print `claude-continue: cron already armed for <cron_fires_at>` and **exit without scheduling anything** (re-scheduling here is how duplicate chains breed).

Otherwise this is the scheduled on-time fire; proceed.

**Why not validate against ccusage?** This very turn is usually the first activity of the NEW 5-hour block, so a fresh fetch returns the new block's `endTime` — always in the future. Comparing against that would misclassify every legitimate fire as "early". ccusage is only used in Step 4 to aim the NEXT tick.

## Step 3 — One-line resume message

Read just the `## Next step` section from the state file. Print exactly:

> `claude-continue: 5h window reset. Next step: <first line of Next step section>`

No summary. No re-introduction.

## Step 4 — Chain the next cron

1. If the state's `cron_job_id` is non-empty, `CronDelete` it first (defensive — never leave two live).
2. Compute and create:

```bash
RESET_AT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-detector.sh" | jq -r '.reset_at // empty')
bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-cron.sh" "$RESET_AT"
# CRON_EXPR=... and FIRES_AT=... lines; fallback to now+5h05m is built in.
```

Call `CronCreate(cron: "<CRON_EXPR>", prompt: "awake tick — claude-continue cron fired; follow the awake-tick skill (read state, one-line resume, chain the next cron)", durable: true, recurring: false)`.

(PLAIN TEXT prompt, never "/awake-tick" — a slash command dies in the parser with "Unknown command" when the skill isn't registered; plain text always wakes Claude and description-matches this skill.)

3. Update state — including the dead-man counter:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_job_id "<new id>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_fires_at "<FIRES_AT value>"
# increment ticks_unattended: read current value, write value+1 (0 or missing → 1)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field ticks_unattended "<current+1>"
```

## Step 5 — Stop

Do not start working on the task. The user may not be present. Hand control back; they will resume manually or by `/awake`.

## Recovery note

Durable one-shot crons expire silently if the CLI stays closed past CronCreate's 7-day window. The SessionStart hook (`read-state.sh --hook`) detects a passed `cron_fires_at` and emits a `CRON_EXPIRED` line — when you see it, suggest the user run `/awake` to re-arm. Do not re-arm autonomously.
