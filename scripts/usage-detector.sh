#!/usr/bin/env bash
# Wraps `ccusage blocks --active --json` with caching and a hard timeout.
# Success cache: 5 min. Failure (negative) cache: 60 s — so an offline machine
# pays the timeout at most once per minute, not on every hook invocation.
# Output: { reset_at, remaining_min, tokens_per_min, total_tokens, cost_usd, fetched_at }
# or { "error": "..." }. Always exits 0.
set -uo pipefail

CACHE_DIR="$HOME/.cache/claude-continue"
CACHE_FILE="$CACHE_DIR/usage.json"
ERR_CACHE_FILE="$CACHE_DIR/usage.error.json"
CACHE_MAX_AGE=300
ERR_CACHE_MAX_AGE=60
TIMEOUT_SEC=10
mkdir -p "$CACHE_DIR"

stat_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

cache_fresh() { # cache_fresh FILE MAX_AGE
  [ -f "$1" ] || return 1
  [ $(( $(date +%s) - $(stat_mtime "$1") )) -lt "$2" ]
}

fail() { # fail MESSAGE — write negative cache and emit
  printf '{"error":"%s"}\n' "$1" | tee "$ERR_CACHE_FILE"
  exit 0
}

if cache_fresh "$CACHE_FILE" "$CACHE_MAX_AGE"; then
  cat "$CACHE_FILE"
  exit 0
fi

if cache_fresh "$ERR_CACHE_FILE" "$ERR_CACHE_MAX_AGE"; then
  cat "$ERR_CACHE_FILE"
  exit 0
fi

command -v npx >/dev/null 2>&1 || fail "npx not available"

# Hard timeout that kills the whole process group (npx spawns node children
# that would otherwise keep the stdout pipe open past the parent's death).
if command -v perl >/dev/null 2>&1; then
  RAW=$(perl -e '
    my $t = shift @ARGV;
    setpgrp(0, 0);
    $SIG{ALRM} = sub { kill "KILL", -$$; exit 1 };
    alarm $t;
    exec @ARGV;
  ' "$TIMEOUT_SEC" npx --yes ccusage@latest blocks --active --json 2>/dev/null)
else
  RAW=$(npx --yes ccusage@latest blocks --active --json 2>/dev/null)
fi

[ -n "$RAW" ] || fail "ccusage returned empty or timed out"

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "$RAW" > "$CACHE_FILE"
  printf '%s\n' "$RAW"
  exit 0
fi

PARSED=$(printf '%s' "$RAW" | jq -c '(.blocks[0] // {}) | {
  reset_at: .endTime,
  remaining_min: (.projection.remainingMinutes // null),
  tokens_per_min: (.burnRate.tokensPerMinute // null),
  total_tokens: (.totalTokens // null),
  cost_usd: (.costUSD // null),
  fetched_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
}' 2>/dev/null)

{ [ -n "$PARSED" ] && [ "$PARSED" != "{}" ]; } || fail "jq parse failed or no active block"

printf '%s\n' "$PARSED" > "$CACHE_FILE"
rm -f "$ERR_CACHE_FILE"
printf '%s\n' "$PARSED"
