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

## Open assumptions to confirm during use

- `${CLAUDE_PLUGIN_ROOT}` resolves in hooks (claude-obsidian's hooks.json doesn't use it; ours assumes it works — fallback: dirname-of-script resolution)
- `claude -c "/awake"` auto-triggers the slash command on session start
- CronCreate `durable: true` actually fires on next launch after CLI restart
- Claude Desktop CronCreate behaves identically

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

