---
name: save-state
description: Manually snapshot the current claude-continue session — goal, plan checkboxes, files touched, decisions, next step. Use when the user types "/save-state", "save", "checkpoint", "snapshot", or before stopping for the day. Archives the previous state and writes a fresh one.
---

# `/save-state` — manual snapshot

User-invoked, so the token cost is what the user asked for.

## Step 1 — Read current state (to preserve runtime fields)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-state.sh" --quiet-if-missing
bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-detector.sh"
```

If a state file exists, extract these fields **verbatim** — they must round-trip unchanged into the new file. Do not regenerate them:

| Field | Source if state exists |
|---|---|
| `awake_enabled` | from existing state |
| `cron_job_id` | from existing state |
| `cron_fires_at` | from existing state |
| `session_started_at` | from existing state (set on first save) |
| `mode_set_at` | from existing state |
| `save_mode` | from existing state |
| `state_id` | from existing state |
| `project` | from existing state |

Helper (run inline before composing the new document):

```bash
STATE_FILE="$HOME/.claude/continue-state/$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-path.sh")/session.md"
preserve() { [ -f "$STATE_FILE" ] && grep "^$1:" "$STATE_FILE" | head -n1; }
preserve awake_enabled
preserve cron_job_id
preserve cron_fires_at
preserve session_started_at
preserve mode_set_at
preserve save_mode
preserve state_id
preserve project
```

If no state yet, set defaults: `awake_enabled: false`, `cron_job_id: ""`, `cron_fires_at: ""`, `session_started_at: <NOW>`, `save_mode: heartbeat`, `state_id: <from state-path.sh>`, `project: <PWD>`.

## Step 2 — Gather from the conversation

- **current_goal**: one sentence
- **status**: in-progress / blocked / done
- **Current task**: short paragraph
- **Plan**: checkable markdown list
- **Files touched**: paths, one per line
- **Recent decisions**: only non-obvious bullets
- **Next step**: the single concrete next action
- **Open questions**: bullets, if any

## Step 3 — Write atomically

Build the full markdown using the **canonical schema** below and pipe to `write-state.sh` (full-write form). The script archives the previous version to `archive/<ISO>.md` before overwriting.

```bash
cat <<'STATE_EOF' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh"
---
project: <preserved or PWD>
state_id: <preserved or from state-path.sh>
last_updated: <now ISO UTC>
save_mode: <preserved or heartbeat>
mode_set_at: <preserved>
current_goal: "<one-sentence goal>"
status: in-progress
awake_enabled: <preserved or false>
cron_job_id: "<preserved>"
cron_fires_at: <preserved>
session_started_at: <preserved or now>
usage_snapshot:
  reset_at: <from usage-detector>
  remaining_min: <from usage-detector>
  tokens_per_min: <from usage-detector>
  total_tokens: <from usage-detector>
  cost_usd: <from usage-detector>
  fetched_at: <from usage-detector>
pending_questions: []
---

## Current task
<paragraph>

## Plan
- [x] done item
- [ ] pending item

## Files touched
- path/to/file

## Recent decisions
- bullet

## Next step
<one concrete action>

## Open questions
- bullet (or omit section)
STATE_EOF
```

## Step 4 — Confirm

Print one line: `State saved → ~/.claude/continue-state/<state_id>/session.md`.

## Notes

- `awake_enabled`, `cron_job_id`, `cron_fires_at` must round-trip — they belong to the cron lifecycle, NOT the session content. Forgetting them disarms auto-resume.
- The `usage_snapshot:` block is required even on first save — `heartbeat.sh` will refresh it in place.
