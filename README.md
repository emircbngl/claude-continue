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

### Option A — clone and load locally (recommended for first try)

```sh
git clone https://github.com/emircbngl/claude-continue.git
claude --plugin-dir ./claude-continue
# inside the Claude session:
/awake
```

`--plugin-dir` loads the plugin for that one session only. No global install, no marketplace step. Good for trying it out.

### Option B — install from a release tag

```sh
git clone --branch claude-continue--v0.1.0 https://github.com/emircbngl/claude-continue.git
claude --plugin-dir ./claude-continue
```

Tags follow Claude's plugin convention: `{name}--v{version}`. Use a tag (instead of `main`) when you want a pinned version that won't shift under you.

### Option C — persistent install via Claude's plugin manager

When the plugin is added to a marketplace you have configured, you can install it like any other plugin:

```sh
claude plugin install claude-continue
# inside the session:
/awake
```

Persistent installs live under `~/.claude/plugins/`. List with `claude plugin list`. Uninstall with `claude plugin uninstall claude-continue`.

### Optional: launchd auto-relaunch (macOS, CLI users only)

```sh
bash claude-continue/scripts/install-launchd.sh
# To remove:
bash claude-continue/scripts/uninstall-launchd.sh
```

The launchd job opens your terminal every ~5 hours and runs `claude -c "/awake"`. Skip this on Claude Desktop — the primary cron mechanism handles continuity inside the app.

### Troubleshooting: "Permission denied" on hook scripts

Some marketplace bundles strip the executable bit when unpacking. If hook output shows `bash: /scripts/heartbeat.sh: Permission denied`, run once:

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

## Star history

<a href="https://star-history.com/#emircbngl/claude-continue&Date">
  <img src="https://api.star-history.com/svg?repos=emircbngl/claude-continue&type=Date" alt="Star history chart for emircbngl/claude-continue" width="640">
</a>

## License

MIT
