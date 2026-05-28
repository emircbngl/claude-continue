---
name: awake
description: This skill should be used when the user types "/awake", "wake up", "continue from where we left off", returns after a usage-limit reset, or wants to start tracking a long task for 5-hour-limit continuity. Reads per-project state, summarizes prior work, asks about pending decisions, schedules a durable cron to resume after the 5-hour reset.
---

# `/awake` — entry point and resumer

Three entry paths. Determine which one applies **before** doing anything else.

## Step 0 — Read the environment

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-state.sh" --quiet-if-missing
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tty-check.sh"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-detector.sh"
```

## Step 1 — Early-exit checks

In order:

1. State exists and `awake_enabled: false` → print "claude-continue is in /rip mode. Use /resurrect to re-enable." and stop.
2. State exists and `status: done` → cleanup:
   - If `cron_job_id` is set, call `CronDelete` with that id.
   - Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-launchd.sh"` (no-op if not installed).
   - Print "Task already finished; auto-wake disabled." and stop.
3. `tty-check.sh` printed `UNATTENDED`:
   - If state has unresolved decisions or `save_mode` is empty, append them to the state file's `pending_questions` via `write-state.sh --field`.
   - Print "Unattended awake: no decisions made. Run /awake interactively to proceed." and stop.
   - **Do not call any other tools.** Token cost must stay ~0.

## Step 2 — Pick the entry path

- **A. Resume**: state exists with `status: in-progress` or `stopped`. Print the 5-line summary (goal / status / next step / files touched / last_updated). Ask each `pending_questions` entry in order, clearing them as answered. Then ask: "Resume from `<next step>`?"
- **B. Fresh start**: no state file. Ask one short question: "What are we working on? Give me a one-sentence goal." Then assemble the full markdown via the schema in `/save-state/SKILL.md` and pipe to `write-state.sh` (NOT `--field` — use the full-write form).
- **C. Mid-session activate**: there is already conversation in this session (chat history exists when `/awake` was invoked fresh). Summarize the conversation into Current task / Plan / Files touched / Recent decisions / Next step, then full-write the state.

In all three paths, ensure the frontmatter has `awake_enabled: true`.

## Step 3 — Show the usage snapshot

Parse the `usage-detector.sh` JSON. Print one line:

> `claude-continue: ~166 dk kaldı (5h pencere) — reset 19:18, harcama $25.62`

## Step 4 — Schedule the durable cron (re-schedule guard ENFORCED)

Before calling `CronCreate`, run this check:

```bash
EXISTING_ID=$(grep "^cron_job_id:" "$STATE_FILE" | sed 's/^cron_job_id: *//' | tr -d '" ')
EXISTING_FIRES=$(grep "^cron_fires_at:" "$STATE_FILE" | sed 's/^cron_fires_at: *//' | tr -d '" ')
NOW_EPOCH=$(date +%s)
FIRE_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXISTING_FIRES" +%s 2>/dev/null || echo 0)
```

If `EXISTING_ID` is non-empty AND `FIRE_EPOCH > NOW_EPOCH` (still future), **skip scheduling** — print "Cron already armed for <fires_at>, reusing." and proceed to Step 5.

Otherwise, compute `reset_at + 5min` from the usage JSON. Convert UTC to local cron fields:

```bash
NEXT_RESET_UTC=$(echo "$USAGE_JSON" | jq -r '.reset_at')           # ISO8601 UTC
# BSD date (macOS):
CRON_FIELDS=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${NEXT_RESET_UTC%.*}" -v+5M "+%M %H %d %m" 2>/dev/null)
# GNU date fallback:
[ -z "$CRON_FIELDS" ] && CRON_FIELDS=$(date -d "$NEXT_RESET_UTC + 5 minutes" "+%M %H %d %m")
CRON_EXPR="$CRON_FIELDS *"
```

Call:

```
CronCreate(
  cron: "<CRON_EXPR>",
  prompt: "/awake-tick",
  durable: true,
  recurring: false
)
```

Persist:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_job_id "<returned id>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_fires_at "<reset_at_plus_5min ISO>"
```

## Step 5 — Confirm

Print one line: `Auto-resume armed: /awake-tick will fire at <local time>.` Then continue what the user asked for.

## Notes

- `${CLAUDE_PLUGIN_ROOT}` is set by the Claude plugin runtime to the plugin's root directory. Confirmed via real plugins (`claude-plugins-official/learning-output-style/hooks/hooks.json`).
- The fresh-write path MUST include the full frontmatter schema documented in `/save-state/SKILL.md` — especially the `usage_snapshot:` block, which `heartbeat.sh` needs to update.
- Pending questions are answered in FIFO order. Don't batch — ask one, get answer, mark resolved, ask next.
