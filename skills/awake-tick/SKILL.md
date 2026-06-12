---
name: awake-tick
description: This skill should be used when the user (or a cron-fired prompt) types "/awake-tick", "awake tick", or when the durable cron from claude-continue fires after a 5-hour usage window. Ultra-minimal — does NOT summarize and does NOT ask the user questions. Confirms the scheduled fire time has arrived, prints a single-line resumed message, and chains the next cron.
---

# `/awake-tick` — cron-fired resumer (ultra-minimal)

Invoked by the durable cron created by `/awake`. The user typically did not just type anything; they may not be at the terminal. Keep tool calls and output tight.

## Step 1 — Read state

```bash
STATE_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-path.sh")
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-state.sh" --quiet-if-missing
```

## Step 2 — Validate (against state, NOT against ccusage)

- If state is missing, `awake_enabled: false`, or `status: done` → silent exit.
- Compare the **state's own** `cron_fires_at` with wall-clock now:

```bash
FIRES=$(grep "^cron_fires_at:" "$STATE_FILE" | sed 's/^cron_fires_at: *//' | tr -d '" ')
FIRES_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$FIRES" +%s 2>/dev/null \
        || date -u -d "$FIRES" +%s 2>/dev/null || echo 0)
NOW=$(date +%s)
```

- `NOW >= FIRES_TS` (or FIRES_TS is 0/unparseable) → this is the scheduled on-time fire; proceed.
- `NOW < FIRES_TS` → fired early somehow; go straight to Step 4 to re-schedule for the stored time, and skip Step 3.

**Why not check ccusage here?** This very turn is usually the first activity of the NEW 5-hour block, so a fresh ccusage fetch returns the new block's `endTime` — always in the future. Comparing against that would misclassify every legitimate fire as "early". ccusage is only used in Step 4 to aim the NEXT tick.

## Step 3 — One-line resume message

Read just the `## Next step` section from the state file. Print exactly:

> `claude-continue: 5h window reset. Next step: <first line of Next step section>`

No summary. No re-introduction.

## Step 4 — Chain the next cron

```bash
RESET_AT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-detector.sh" | jq -r '.reset_at // empty')
bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-cron.sh" "$RESET_AT"
# CRON_EXPR=... and FIRES_AT=... lines; fallback to now+5h05m is built in.
```

Call `CronCreate(cron: "<CRON_EXPR>", prompt: "/awake-tick", durable: true, recurring: false)`.

Update state:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_job_id "<new id>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_fires_at "<FIRES_AT value>"
```

## Step 5 — Stop

Do not start working on the task. The user may not be present. Hand control back; they will resume manually or by `/awake`.

## Recovery note

Durable one-shot crons expire silently if the CLI stays closed past CronCreate's 7-day window. The SessionStart hook (`read-state.sh --hook`) detects a passed `cron_fires_at` and emits a `CRON_EXPIRED` line — when you see it, suggest the user run `/awake` to re-arm. Do not re-arm autonomously.
