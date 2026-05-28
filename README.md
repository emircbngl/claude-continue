# claude-continue

Survive Claude's 5-hour usage limit. **Same-chat continuity** via durable cron; state-file resume as fallback; `/rip` kill switch; optional macOS launchd auto-relaunch. **Zero idle token cost.**

## What it does

When you're working with Claude and the 5-hour usage window resets, you normally lose context. `claude-continue` solves this two ways:

1. **Same chat (primary)**: `CronCreate(durable: true)` schedules a tick that fires inside the *same* REPL right after the window resets. The conversation never changes, the context never drops.
2. **New chat fallback**: If the CLI was closed, a per-project state file lets `/awake` rebuild context in a new session. Optional macOS launchd job can auto-launch your terminal at the right time.

## Commands

| Command | Purpose |
|---|---|
| `/awake` | Activate or resume. Three entry modes: fresh start, resume from state, or activate mid-conversation. |
| `/save-state` | Manual snapshot of the current session. |
| `/awake-tick` | (Auto) Fired by the durable cron; ultra-minimal, just chains the next one. |
| `/rip` | Kill switch — cancels cron, uninstalls launchd, disables hooks. Reversible. |
| `/resurrect` | Undo `/rip` — restores from `archive/before-rip.md`. |

## Why it's cheap

- **Heartbeats are pure bash** — no Claude turn, no tokens. State updates happen in `scripts/heartbeat.sh`, invoked from a `PostToolUse` hook.
- **Hooks never inject prompts** by default. They only emit a single line when the 5-hour limit is within 30 minutes (`warn-emit.sh`).
- **Usage detection via `ccusage`** with a 5-minute filesystem cache.
- **`awake_enabled: false` default** — until you explicitly `/awake`, every hook is a no-op.

| Trigger | Frequency | Tokens |
|---|---|---|
| Every Edit/Write | per edit | **0** |
| 10-min heartbeat | every 10 min | **0** |
| Limit warning | ≤2× per 5h window | ~10–20 |
| `awake-tick` cron fire | 5h | ~50–100 |
| `/awake`, `/save-state`, `/rip`, `/resurrect` | on demand | user-driven cost |

## Install

```sh
cd "claude continue skill"
# Local development:
claude --plugin-dir ./claude-continue
# Or marketplace install (when published)
claude plugin install ./claude-continue

# inside the Claude session:
/awake
```

If installing from a `.zip` bundle, marketplace unpackers sometimes strip the executable bit on shell scripts. If `bash: /scripts/heartbeat.sh: Permission denied` appears in your hook output, run once:

```sh
chmod +x "$(dirname "$(find ~/.claude/plugins -name plugin.json -path '*claude-continue*' | head -1)")"/scripts/*.sh
```

For the optional auto-launch on macOS:

```sh
bash claude-continue/scripts/install-launchd.sh
```

To remove:

```sh
bash claude-continue/scripts/uninstall-launchd.sh
```

## Requirements

- macOS (launchd part) or any OS (core skills)
- `bash`, `jq` (for usage parsing)
- `npx` available on PATH (for `ccusage`) — `npm i -g ccusage` for faster repeated calls

## State location

`~/.claude/continue-state/<state_id>/session.md`

The `state_id` is derived in order of preference: git-root hash → dash-encoded cwd → session id. This means working from different shells on the same project gives the same state file.

## Claude Desktop

Skills and hooks load in Desktop too. `CronCreate` works the same way. `install-launchd.sh` detects Desktop and skips itself.

## Files

```
claude-continue/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── skills/{awake,awake-tick,save-state,rip,resurrect}/SKILL.md
├── scripts/{state-path,read-state,write-state,heartbeat,warn-emit,
│             tty-check,usage-detector,install-launchd,uninstall-launchd}.sh
├── scripts/com.user.claude-continue.plist.template
└── tasks/todo.md
```

## License

MIT
