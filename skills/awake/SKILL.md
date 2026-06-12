---
name: awake
description: This skill should be used when the user types "/awake", "wake up", "continue from where we left off", returns after a usage-limit reset, or wants to start tracking a long task for 5-hour-limit continuity. Reads per-project state, summarizes prior work, asks about pending decisions, schedules a durable cron to resume after the 5-hour reset.
---

# `/awake` — entry point and resumer

Three entry paths. Determine which one applies **before** doing anything else.

## Step 0 — Read the environment (cheap calls only)

```bash
STATE_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-path.sh")
STATE_FILE="$HOME/.claude/continue-state/$STATE_ID/session.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-state.sh" --quiet-if-missing
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tty-check.sh"
```

Do NOT call `usage-detector.sh` yet — it can cost up to 10 s and the unattended path must stay near-free. It runs in Step 3, attended paths only.

(`tty-check.sh` reports UNATTENDED only when `CLAUDE_CONTINUE_UNATTENDED=1` is set — the launchd job sets it; a user-typed `/awake` is always ATTENDED.)

## Step 1 — Early-exit checks

In order — **UNATTENDED first**, so an unattended fire never pays for the later checks' tool calls:

1. `tty-check.sh` printed `UNATTENDED`:
   - If state has unresolved decisions or `save_mode` is empty, append them to `pending_questions` — **only the ones not already listed there** (compare against the Step 0 output; on repeated unattended fires this step must produce no change).
   - Print "Unattended awake: no decisions made. Run /awake interactively to proceed." and stop.
   - **Do not call any other tools.**
2. State exists and `awake_enabled: false` → print "claude-continue is in /rip mode. Use /resurrect to re-enable." and stop.
3. State exists and `status: done` → full teardown (mirror /rip):
   - If `cron_job_id` is set, call `CronDelete` with that id.
   - Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-launchd.sh"` (no-op if not installed).
   - `write-state.sh --field awake_enabled false`, `--field cron_job_id ""`, `--field cron_fires_at ""`.
   - `rm -f "$HOME/.cache/claude-continue/warn-$STATE_ID"`.
   - Print "Task already finished; auto-wake torn down." and stop.

## Step 2 — Pick the entry path

- **A. Resume**: state exists with `status: in-progress` or `stopped`. Print the 5-line summary (goal / status / next step / files touched / last_updated). Ask each `pending_questions` entry in order, clearing them as answered. Then ask: "Resume from `<next step>`?"
- **B. Fresh start**: no state file. Ask one short question: "What are we working on? Give me a one-sentence goal." Then assemble the full markdown via the schema in `/save-state/SKILL.md` and pipe to `write-state.sh` (full-write form; it rejects empty stdin).
- **C. Mid-session activate**: there is already conversation in this session (chat history exists when `/awake` was invoked fresh). Summarize the conversation into Current task / Plan / Files touched / Recent decisions / Next step, then full-write the state.

In all three paths, ensure the frontmatter has `awake_enabled: true`.

## Step 3 — Show the usage snapshot

Parse the `usage-detector.sh` JSON. Print one line:

> `claude-continue: ~166 dk kaldı (5h pencere) — reset 19:18, harcama $25.62`

If the JSON has an `error` field, say so briefly and continue — `next-cron.sh` has a built-in fallback.

## Step 4 — Schedule the durable cron (re-schedule guard ENFORCED)

First check whether a future-dated cron already exists:

```bash
EXISTING_ID=$(grep "^cron_job_id:" "$STATE_FILE" | sed 's/^cron_job_id: *//' | tr -d '" ')
EXISTING_FIRES=$(grep "^cron_fires_at:" "$STATE_FILE" | sed 's/^cron_fires_at: *//' | tr -d '" ')
NOW_EPOCH=$(date +%s)
FIRE_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXISTING_FIRES" +%s 2>/dev/null \
          || date -u -d "$EXISTING_FIRES" +%s 2>/dev/null || echo 0)
```

If `EXISTING_ID` is non-empty AND `FIRE_EPOCH -gt NOW_EPOCH` → **skip scheduling**; print "Cron already armed for <fires_at>, reusing." and go to Step 5.

Otherwise: if `EXISTING_ID` is non-empty (but stale/unparseable), call `CronDelete` with it FIRST — a cleared `cron_fires_at` must never stack a second live cron on top of an old one. Then compute the fire time with the dedicated script (handles millisecond ISO, UTC→local, and a now+5h05m fallback when reset_at is null/unparseable):

```bash
RESET_AT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-detector.sh" | jq -r '.reset_at // empty')
bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-cron.sh" "$RESET_AT"
# Output:
#   CRON_EXPR=18 22 28 05 *
#   FIRES_AT=2026-05-28T19:18:00Z
```

Call:

```
CronCreate(
  cron: "<CRON_EXPR value>",
  prompt: "awake tick — claude-continue cron fired; follow the awake-tick skill (read state, one-line resume, chain the next cron)",
  durable: true,
  recurring: false
)
```

**The prompt must be PLAIN TEXT, never a slash command.** Live-tested: a cron-fired "/awake-tick" goes through the slash-command parser and dies with "Unknown command" if the skill isn't registered in that session — Claude never wakes. Plain text always arrives as a normal message (waking Claude unconditionally) and triggers the skill via description match.

Also note: the runtime may downgrade `durable: true` to session-only (observed on Claude Desktop: "Session-only, not written to disk"). Same-chat continuity with the chat open is unaffected; if the session dies, the SessionStart hook's CRON_EXPIRED line is the recovery path.

Persist:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_job_id "<returned id>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh" --field cron_fires_at "<FIRES_AT value>"
```

## Step 5 — Confirm

Print one line: `Auto-resume armed: /awake-tick will fire at <local time> — in THIS chat, no new window.` Then continue what the user asked for.

Do NOT suggest installing launchd. It is a niche opt-in for unattended machines; the durable cron already re-activates the existing chat in place (CLI and Desktop alike). Mention launchd only if the user explicitly asks how to resume with the app fully closed and nobody at the machine.

## Notes

- `${CLAUDE_PLUGIN_ROOT}` is set by the Claude plugin runtime (confirmed via `claude-plugins-official/learning-output-style`).
- Never compute cron fields with inline `date` arithmetic — always use `next-cron.sh`; it is the single tested implementation of the UTC→local conversion.
- The fresh-write path MUST include the full frontmatter schema from `/save-state/SKILL.md`, including the `usage_snapshot:` block and `cron_fires_at` (write-state.sh stores it WITHOUT quotes; the greps above strip quotes defensively either way).
- Pending questions are answered in FIFO order — ask one, get the answer, mark resolved, ask the next.
