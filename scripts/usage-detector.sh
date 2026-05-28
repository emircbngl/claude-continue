#!/usr/bin/env bash
# Wraps `ccusage blocks --active --json` with 5-minute filesystem cache and 10s timeout.
# Outputs a normalized JSON object: { reset_at, remaining_min, tokens_per_min, total_tokens, cost_usd, fetched_at }
# Graceful: if ccusage/npx/jq missing or fails, returns {} with error field.
set -uo pipefail

CACHE_DIR="$HOME/.cache/claude-continue"
CACHE_FILE="$CACHE_DIR/usage.json"
CACHE_MAX_AGE=300
TIMEOUT_SEC=10
mkdir -p "$CACHE_DIR"

stat_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

if [ -f "$CACHE_FILE" ]; then
  AGE=$(( $(date +%s) - $(stat_mtime "$CACHE_FILE") ))
  if [ "$AGE" -lt "$CACHE_MAX_AGE" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

if ! command -v npx >/dev/null 2>&1; then
  printf '{"error":"npx not available"}\n'
  exit 0
fi

# Portable timeout via perl alarm — macOS lacks `timeout(1)` natively
if command -v perl >/dev/null 2>&1; then
  RAW=$(perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SEC" npx --yes ccusage@latest blocks --active --json 2>/dev/null)
else
  RAW=$(npx --yes ccusage@latest blocks --active --json 2>/dev/null)
fi

if [ -z "$RAW" ]; then
  printf '{"error":"ccusage returned empty or timed out"}\n'
  exit 0
fi

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

if [ -z "$PARSED" ] || [ "$PARSED" = "{}" ]; then
  printf '{"error":"jq parse failed"}\n'
  exit 0
fi

printf '%s\n' "$PARSED" > "$CACHE_FILE"
printf '%s\n' "$PARSED"
