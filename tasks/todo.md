# tasks/todo.md

## Implementation

- [x] Plugin scaffold (`.claude-plugin/plugin.json`)
- [x] Shell utilities: `state-path.sh`, `read-state.sh`, `write-state.sh`, `tty-check.sh`, `usage-detector.sh`
- [x] `heartbeat.sh` (pure shell, no Claude tokens)
- [x] `warn-emit.sh` (UserPromptSubmit single-line warning)
- [x] `hooks/hooks.json` (SessionStart + PostToolUse + UserPromptSubmit)
- [x] Skill stubs: `awake`, `awake-tick`, `save-state`, `rip`, `resurrect`
- [x] launchd `plist.template` + `install-launchd.sh` + `uninstall-launchd.sh`
- [x] README.md
- [x] Smoke test: `claude plugin validate ./claude-continue` ✔ passed
- [x] Smoke test: `claude --plugin-dir ... --print "say OK"` ✔ "OK" returned, no load errors
- [x] Smoke test: `heartbeat.sh` updates state fields (last_updated, remaining_min, reset_at, cost_usd, …)
- [x] Smoke test: heartbeat throttle (~40ms early-exit when within 10-min window)
- [x] Smoke test: `usage-detector.sh` returns normalized JSON (reset_at, remaining_min, …)
- [x] Smoke test: WARN round-trip (heartbeat writes marker → warn-emit prints + deletes → second call silent)

## Verification (from plan)

- [ ] Fresh start: state yokken `/awake` doğru davranır
- [ ] Mid-session activate: var olan sohbette `/awake`
- [ ] Same-chat continuity: 60s cron ile `/awake-tick` aynı sohbette tetiklenir
- [ ] Chain: `awake-tick`'in attığı yeni cron `CronList`'te
- [ ] Unattended path: `echo "/awake" | claude -p` token harcamadan exit
- [ ] Done state: cron + launchd self-uninstall
- [ ] `/rip` + `/resurrect` round-trip
- [ ] Token leak: 100 turn → hooks tek prompt enjeksiyonu yapmıyor
- [ ] WARN tetikleyici: `remaining_min` mock'la 25 → UserPromptSubmit'te tek satır
- [ ] ccusage cache: 5dk içinde tekrar çağırma hızlı
- [ ] launchd opsiyonel: install ile Terminal açılır
- [ ] Desktop sanity: plugin yüklenir, launchd "Desktop tespit edildi" der

## v0.1.2 — Safety audit ("iş bitse de zorla kaldırma yapar mı?")

3-angle audit (runaway triggers / cleanup gaps / concurrency), 24 candidates,
20 CONFIRMED + 4 PLAUSIBLE, 0 refuted. Answer before fixes: YES — it forced
wake-ups forever. Fixes:

- [x] **Dead-man switch**: `ticks_unattended` counter — awake-tick increments each
  fire, UserPromptSubmit hook (warn-emit.sh) resets to 0 on any real user prompt.
  2 windows with zero user activity → chain pauses, cron fields cleared, one-line
  notice. (last_updated could NOT be the signal: the tick's own Bash calls bump it
  via the PostToolUse heartbeat.)
- [x] **done lifecycle closed**: awake-tick's done-check now tears down (CronDelete
  + fields cleared + awake_enabled false + launchd uninstall) instead of silently
  exiting; /awake's done path mirrors /rip fully; /save-state template no longer
  hardcodes `status: in-progress`.
- [x] **launchd rebuilt window-free** (user requirement: never open a new terminal —
  re-activate the existing chat): plist now runs `launchd-fire.sh`, a pure-shell
  guard that (1) self-uninstalls when plugin/project/state is gone or status is
  done/ripped, (2) skips when state is stale >24h or any claude is already running,
  (3) otherwise launches HEADLESS `claude -c -p "/awake"` — no window, no REPL, the
  queued durable cron fires, process exits. Fire script is rendered into
  ~/.cache/claude-continue/ so it survives plugin uninstall long enough to
  self-clean. Logs moved /tmp → ~/.cache, removed on uninstall.
- [x] **Duplicate-chain guards**: /awake deletes a stale EXISTING_ID before
  re-scheduling; awake-tick's early-fire branch exits instead of re-scheduling;
  awake-tick Step 4 deletes the old id before CronCreate.
- [x] **SessionStart token tax bounded**: read-state --hook emits ONE stale line
  (not the full state) when last_updated >7 days; heartbeat exits instantly on
  abandoned state.
- [x] **UNATTENDED check moved to #1** in /awake (before any tool-bearing checks);
  usage-detector deferred out of Step 0; pending_questions append made idempotent.
- [x] **/rip honesty**: documents that CronList is session-scoped, always tries
  CronDelete with the stored id, and explains awake_enabled:false is the
  authoritative kill (orphan crons fire once, hit the guard, die). Offers
  `uninstall-launchd.sh --all` when other projects' agents exist.
- [x] **uninstall-launchd --all**: glob-based sweep for orphans (renamed/moved
  projects whose state-id no longer resolves).
- [x] README: uninstall-order warning (rip/launchd before plugin uninstall).

Deferred (low risk, v0.2): mkdir-mutex for concurrent heartbeat/save writers
(single-writer atomicity already holds; flip-flop window is cosmetic), pinning
launchd resume to a session id instead of `-c` (headless+deferred /awake makes
hijack consequence a no-op line).

### v0.1.2 safety test matrix (all passing)

- [x] warn-emit resets nonzero ticks_unattended to 0
- [x] read-state --hook: >7d stale → single STALE_STATE line, no full dump
- [x] heartbeat: abandoned state → instant exit (31 ms)
- [x] launchd-fire: plugin dir missing → self-uninstall branch
- [x] launchd-fire: status done → exits without launching claude
- [x] launchd-fire: claude already running → skips headless launch
- [x] uninstall-launchd --all: clean no-op on empty set
- [x] plugin validate passes

## Phase-1 live test results (2026-06-12, Claude Desktop session)

- ✅ **Same-chat fire PROVEN**: a one-shot cron created at 23:24 fired at exactly
  23:26:14 and enqueued its prompt INTO THE SAME CHAT. The core mechanism works.
- ✅ One-shot auto-delete confirmed (CronList empty after fire).
- ❌→fixed **Slash prompts are unsafe**: the fired "/awake-tick" hit the
  slash-command parser and died with "Unknown command" (plugin not loaded in that
  session) — Claude was never woken. ALL cron/launchd prompts are now PLAIN TEXT
  ("awake tick — claude-continue cron fired; follow the awake-tick skill"), which
  always wakes Claude and triggers the skill via description match. (Fixed in v0.1.3.)
- ⚠️ **durable: true downgraded to session-only on Desktop** ("Session-only, not
  written to disk, dies when Claude exits"). Same-chat continuity with the chat
  open is unaffected (that cron lives as long as the chat does). The closed-chat
  queue scenario needs CLI re-verification (Phase 3); the SessionStart
  CRON_EXPIRED line is the recovery path either way.

## v0.1.4 — Phase 1 LIVE test (the core mechanism, proven in-chat)

Ran the durable cron live, twice, in a real Claude session. Findings:

1. **CONFIRMED — same-chat fire works.** A durable one-shot cron armed for T fired a
   prompt that appeared as a NEW TURN IN THE SAME CHAT at ~T. This is the whole
   plugin's premise; it holds. No new window, no new session.
2. **CONFIRMED & FIXED — slash-command prompts die in the parser.** First attempt used
   `prompt: "/awake-tick"`. When the plugin is not registered in that session the
   slash command is rejected ("Unknown command") and Claude never wakes — the user's
   "kaldırmadı seni" (it didn't wake you). Fix (v0.1.3): the cron and launchd now
   enqueue a PLAIN-TEXT prompt ("awake tick — claude-continue cron fired; follow the
   awake-tick skill …") which always opens a turn and description-matches the skill.
   Second attempt with plain text woke the chat correctly.
3. **CONFIRMED & FIXED — cron jitter broke the early-fire guard.** CronCreate delivered
   the prompt ~23 s BEFORE `cron_fires_at` (its docs: "up to 90 s early"). The guard's
   naïve `NOW < FIRES_TS` test would have classified this real, on-time fire as "early"
   and skipped re-chaining — silently ending the chain after one tick. Fix (v0.1.4):
   awake-tick Step 2.4 now allows a 120 s jitter window (`NOW < FIRES_TS - 120`), so
   only a fire MORE than 2 min early counts as a stray double-fire.

### Phase 1 test matrix (all passing, live)

- [x] plain-text durable cron → prompt appears as a new turn in the SAME chat at fire time
- [x] slash-command prompt does NOT wake an unregistered session (root cause of attempt 1)
- [x] halt checks read correctly on the live fire (awake_enabled / status / ticks_unattended=0)
- [x] resume line prints the state's actual `## Next step`
- [x] jitter: a tick armed for `:39` fired at `:16` (23 s early) and is still treated as on-time

## Open assumptions to confirm during use

- `${CLAUDE_PLUGIN_ROOT}` resolves in hooks (claude-obsidian's hooks.json doesn't use it; ours assumes it works — fallback: dirname-of-script resolution)
- Does CronCreate `durable: true` persist across restarts on the CLI? (Desktop downgrades it to session-only — observed live in Phase 1. Phase 3 covers CLI.)
- Plain-text cron prompt description-matches the awake-tick skill when the plugin IS loaded (Phase 2 confirms; Phase 1 woke the chat even WITHOUT the plugin loaded, via the plain-text turn)

## Review

### Done in this session

- Greenfield scaffold under `claude-continue/` per the approved plan
- 9 shell scripts: `state-path`, `read-state`, `write-state`, `tty-check`, `usage-detector`, `heartbeat`, `warn-emit`, `install-launchd`, `uninstall-launchd`
- 5 skill manifests: `awake`, `awake-tick`, `save-state`, `rip`, `resurrect`
- `hooks/hooks.json` wiring SessionStart, PostToolUse, UserPromptSubmit (no Stop hook — by design, to avoid per-turn token cost)
- `com.user.claude-continue.plist.template` + install/uninstall scripts (multi-project safe via `${STATE_ID}` suffix)
- README, plugin.json, this todo.md

### Verified locally

- Plugin manifest validates clean
- Plugin loads via `--plugin-dir` and runs a prompt successfully
- `ccusage`-driven usage detection returns expected JSON (reset_at, remaining_min)
- Heartbeat updates state file in place, then early-exits within the 10-min throttle
- WARN marker → `warn-emit.sh` round-trip works end-to-end

### Remaining (requires real usage, not a unit test)

- Same-chat continuity: a real CronCreate fire — must be exercised inside an interactive Claude session
- `claude -c "/awake"` auto-trigger behaviour on next launch
- Claude Desktop side: verify SKILL.md and hooks resolve there
- Multi-project launchd isolation: install for two different cwds and confirm distinct `Label`s and plists

### Notes for next iteration

- Could add `ccusage` install hint into `/awake` first-run output if `npx` not found
- `state-path.sh` currently strips leading dash from cwd-encoded path — different from Claude's internal convention (`-Users-foo`) but unique and stable; not changing unless it causes a collision
- Heartbeat doesn't archive on every save (only on full `write-state.sh` writes) — intentional, but means a corrupt sed could lose state. Mitigation: `/save-state` does full rewrites with archive

## Post-review fixes (15 findings addressed)

Applied after `/code-review` max-effort pass:

- [x] **#1, #3 (CronCreate / `claude -c` slash auto-trigger)**: SKILL.md descriptions rewritten to literally include "/awake-tick" / "/awake" trigger phrases so auto-match works either as user input or cron-fired prompt
- [x] **#2 (heartbeat sed can't add missing fields)**: heartbeat.sh now seeds the `usage_snapshot:` block if absent; `upd()` rewritten as awk-based field updater that handles both indented and top-level keys safely
- [x] **#4 (last_updated bumped before ccusage)**: heartbeat.sh now bumps `last_updated` ONLY when usage refresh succeeds (`USAGE_OK=1`); failed fetches no longer lock out recovery
- [x] **#5 (sed metachar in `--field`)**: write-state.sh `--field` now uses awk -v (no shell interpolation in regex); verified with `foo | bar & baz \ qux`
- [x] **#6 (nested fields in `--field`)**: awk matches both `^  key: ` and `^key: ` patterns; falls back to top-level insert before closing `---`
- [x] **#7 (upd 2-space indent)**: same awk-based approach handles both indentations
- [x] **#8 (PostToolUse misses MultiEdit/NotebookEdit)**: matcher widened to `"Edit|Write|MultiEdit|NotebookEdit"`
- [x] **#9 (no re-schedule guard)**: `/awake/SKILL.md` Step 4 now contains explicit shell logic (`EXISTING_ID` + `FIRE_EPOCH > NOW_EPOCH` check) before `CronCreate`
- [x] **#10 (warn-emit no awake_enabled guard)**: warn-emit.sh now checks state file's `awake_enabled: true` and deletes the marker if disabled; `/rip` also explicitly clears the WARN marker
- [x] **#11 (CLAUDE_PLUGIN_ROOT reliability)**: verified — `claude-plugins-official/learning-output-style` uses the same pattern; assumption confirmed. Plus all scripts have `SCRIPT_DIR=...dirname` fallback for script-to-script calls
- [x] **#12 (UTC→local TZ conversion)**: explicit `date -j -u -f ... -v+5M "+%M %H %d %m"` formula in both `/awake/SKILL.md` and `/awake-tick/SKILL.md` (BSD + GNU fallback)
- [x] **#13 (/save-state preserves runtime fields manually)**: `/save-state/SKILL.md` now has an explicit `preserve()` helper and a runtime-fields table; canonical state schema documented in one place
- [x] **#14 (state-id length unbounded)**: state-path.sh caps output at 80 chars; if longer, replaces with `cwd-<basename>-<sha-12>`
- [x] **#15 (plugin install +x)**: README documents a one-line `chmod +x ...` recovery if marketplace install strips executable bits
- Refuted (no fix needed):
  - Plist `&amp;&amp;` — correct plist XML for embedding `&&` (decoded by launchctl parser)
  - heartbeat `set -uo pipefail` missing `-e` — explicit `|| exit 0` chains cover all failure paths
  - Non-ASCII Turkish in warn-emit — UTF-8 is fine in modern shells

### Re-verified after fixes

- [x] heartbeat seeds `usage_snapshot:` block when missing → populates from ccusage in one pass
- [x] write-state.sh `--field` round-trips a value containing `| & \` unchanged
- [x] write-state.sh `--field` can add a new key
- [x] warn-emit.sh silent + clears marker when `awake_enabled: false`
- [x] `claude plugin validate` still passes after all changes

## v0.1.1 — Second review round (ultracode workflow, 39 findings)

A 5-angle finder fan-out produced 39 deduped candidates; the verify stage hit the
session limit (ironically, the exact problem this plugin solves), so verification
was done by hand with executable tests. Headline defects, all CONFIRMED by test:

1. **Both UTC→local cron formulas were broken** (awake: `-v+5M` and the output
   format placed after the operand are silently ignored AND `-u` makes output UTC;
   awake-tick: missing `-u` parses UTC as local). Fixed by replacing inline date
   arithmetic with a single tested script, `scripts/next-cron.sh` (epoch-based,
   millisecond-ISO tolerant, now+5h05m fallback). Proven: `10:00Z → 05 13` (+03).
2. **awake-tick's early/on-time test was inverted in practice** — the tick turn
   itself starts the new ccusage block, so the fresh `endTime` is always in the
   future and every legitimate fire would be classified "early". Now validates
   against the state's own `cron_fires_at`; ccusage only aims the NEXT tick.
3. **tty-check could never print ATTENDED** (hooks and the Bash tool both run on
   pipes). Replaced the TTY test with an explicit `CLAUDE_CONTINUE_UNATTENDED=1`
   env signal set only by the launchd command line.
4. **Offline = 10s penalty on every Edit** (no negative cache + last_updated only
   bumping on success). Added a 60-s error cache; perl timeout now kills the whole
   process group (npx's node children kept the pipe open before).
5. **awk -v mangled backslashes** (C-escape processing). All values now flow via
   ENVIRON. Proven: `C:\new\table | x & y` round-trips intact.
6. **Key-matching required a trailing space** (`key:` with empty value never
   matched). Both updaters now use index-based prefix checks; heartbeat collapsed
   8 awk+mv passes into ONE (single tmp.$$, frontmatter-gated — body lines with
   key-like prefixes proven untouched).
7. **Empty-stdin full write destroyed state.** Now buffered first and rejected.
8. **SessionStart hook leaked full state into every session's context** even when
   awake was disabled. `read-state.sh --hook` is silent unless `awake_enabled:
   true`, and emits CRON_EXPIRED when a scheduled fire was missed (7-day durable
   cron expiry recovery path).
9. **`/resurrect` clobbered post-rip saves** (wholesale archive copy). Now a flag
   flip on the live state; archive copy only as disaster recovery.
10. **`/save-state` wiped pending_questions** (schema hardcoded `[]`). Preserve
    table + schema updated.
11. **state-path length cap didn't cap** (long basename) and git-repo subdirs got
    different ids in the fallback. Hash source is now the id-defining path,
    basename truncated to 40 chars. Proven: 100-char dir → 57-char id.
12. **install-launchd sed broke on `&`/`|` in paths.** Replacement values now
    escaped. Proven with `/Users/x/R&D project`.
13. Smaller: WARN marker moved /tmp → ~/.cache (symlink hardening), PostToolUse
    matcher now includes Bash, `/rip` sweeps ALL `/awake-tick` crons via CronList,
    README chmod one-liner fixed (`.claude-plugin` sibling), iTerm AppleScript
    caveat warned at install time, non-TTY install skips the interactive prompt.

Accepted limitations (documented, not fixed): launchd StartInterval anchors to
load time, not the usage boundary; iTerm/Warp/Ghostty need a different AppleScript
verb (v0.2); Bash-tool file writes only heartbeat via the Bash matcher.

### v0.1.1 test matrix (all passing)

- [x] next-cron.sh: future ISO+ms → correct local fields (10:00Z → "05 13" at +03)
- [x] next-cron.sh: past / null / empty reset_at → now+5h05m fallback
- [x] --field ENVIRON round-trip: `C:\new\table | x & y` unchanged
- [x] --field on valueless `cron_job_id:` updates frontmatter, body line untouched
- [x] empty-stdin full write rejected (exit 1, state intact)
- [x] heartbeat single pass: seeds snapshot, bumps last_updated, no tmp leftovers
- [x] negative cache: offline second call 10 ms
- [x] state-path: 100-char dir → 57-char id (≤80)
- [x] sed escaping: `R&D project` renders intact in plist
- [x] tty-check: ATTENDED default, UNATTENDED only with env
- [x] read-state --hook: silent when disabled; CRON_EXPIRED on stale cron_fires_at
- [x] `claude plugin validate` passes

