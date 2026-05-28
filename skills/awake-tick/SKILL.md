---
name: awake-tick
description: This skill should be used when the user (or a cron-fired prompt) types "/awake-tick", "awake tick", or when the durable cron from claude-continue fires after a 5-hour usage window. Ultra-minimal — does NOT summarize and does NOT ask the user questions. Verifies the new usage window has begun, prints a single-line resumed message, and chains the next cron.
---

# `/awake-tick` — cron-fired resumer (ultra-minimal)

Invoked by the durable cron created by `/awake`. The user typically did not just type anything; they may not be at the terminal. Keep tool calls and output tight.

## Step 1 — Read state and usage

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-state.sh" --quiet-if-missing
bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-detector.sh"
```

## Step 2 — Validate

- If state is missing or has `awake_enabled: false` or `status: done` → silent exit.
- Parse the usage JSON. If `reset_at` is now in the past relative to wall-clock now → the new window has begun, proceed. If `reset_at` is still in the future → cron fired early; recompute and re-schedule (Step 4) without printing the resume message.

## Step 3 — One-line resume message

Read just the `## Next step` section from the state file. Print exactly:

> `claude-continue: 5h window reset. Next step: <first line of Next step section>`

No summary. No re-introduction.

## Step 4 — Chain the next cron

Compute the *next* `reset_at + 5min`. **Timezone conversion** (CronCreate cron is local-time, `reset_at` is UTC):

```bash
# In bash:
NEXT_RESET_UTC=$(echo "$USAGE_JSON" | jq -r '.reset_at')           # e.g. "2026-05-29T00:00:00.000Z"
NEXT_FIRE_LOCAL=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${NEXT_RESET_UTC%.*}" -v+5M "+%M %H %d %m" 2>/dev/null \
              || date -d "$NEXT_RESET_UTC + 5 minutes" "+%M %H %d %m")
# NEXT_FIRE_LOCAL is now "M H DoM Mon" — append " *" for the cron expression.
```

If `date` parsing fails, fall back to adding 5h05m to wall-clock now in local time.

Call:

```
CronCreate(
  cron: "<M H DoM Mon> *",
  prompt: "/awake-tick",
  durable: true,
  recurring: false
)
```

Update state:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_job_id "<new id>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_fires_at "<new fire ISO>"
```

## Step 5 — Stop

Do not start working on the task. The user may not be present. Hand control back; they will resume manually or by `/awake`.
