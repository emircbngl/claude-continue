#!/usr/bin/env bash
# Computes the next cron fire time from a UTC reset_at timestamp.
# Usage: next-cron.sh [reset_at_iso]
#   reset_at_iso: e.g. "2026-05-28T19:00:00.000Z" or "2026-05-28T19:00:00Z" (milliseconds optional)
#   If missing/unparseable, falls back to now + 5h05m.
# Output (two lines):
#   CRON_EXPR=<M> <H> <DoM> <Mon> *      (LOCAL time fields, ready for CronCreate)
#   FIRES_AT=<ISO UTC of the fire time>
# Always exits 0; fallback is built in.
set -uo pipefail

RESET_AT="${1:-}"
SAFETY_SEC=300          # fire 5 min after the window resets
FALLBACK_SEC=18300      # 5h05m from now if reset_at is unusable

epoch_from_iso() {
  # Strip milliseconds and trailing Z: 2026-05-28T19:00:00.000Z -> 2026-05-28T19:00:00
  local iso="${1%%Z}"
  iso="${iso%%.*}"
  # BSD date (macOS) then GNU date
  date -j -u -f "%Y-%m-%dT%H:%M:%S" "$iso" +%s 2>/dev/null \
    || date -u -d "${iso}Z" +%s 2>/dev/null \
    || echo ""
}

NOW=$(date +%s)
RESET_EPOCH=""
[ -n "$RESET_AT" ] && [ "$RESET_AT" != "null" ] && RESET_EPOCH=$(epoch_from_iso "$RESET_AT")

if [ -n "$RESET_EPOCH" ] && [ "$RESET_EPOCH" -gt "$NOW" ] 2>/dev/null; then
  FIRE_EPOCH=$(( RESET_EPOCH + SAFETY_SEC ))
else
  FIRE_EPOCH=$(( NOW + FALLBACK_SEC ))
fi

# Format the fire time in LOCAL time for the cron expression (BSD -r, GNU -d @)
CRON_FIELDS=$(date -r "$FIRE_EPOCH" "+%M %H %d %m" 2>/dev/null \
           || date -d "@$FIRE_EPOCH" "+%M %H %d %m" 2>/dev/null)
FIRES_AT_ISO=$(date -u -r "$FIRE_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
            || date -u -d "@$FIRE_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

printf 'CRON_EXPR=%s *\n' "$CRON_FIELDS"
printf 'FIRES_AT=%s\n' "$FIRES_AT_ISO"
