#!/usr/bin/env bash
# Prints the state-id (directory name) for the current working dir.
# Fallback order: git-root > dash-encoded-cwd > session-id
# Caps length at 80 chars; if longer, replaces with a hash-stable short form.
set -euo pipefail

MAX_LEN=80

sanitize() { tr -c '[:alnum:]-_.' '-' | sed 's/--*/-/g; s/^-//; s/-$//'; }

emit() {
  local s="$1"
  if [ "${#s}" -gt "$MAX_LEN" ]; then
    local base sha
    base=$(basename "$PWD" 2>/dev/null | sanitize)
    sha=$(printf '%s' "$PWD" | shasum | cut -c1-12)
    printf 'cwd-%s-%s\n' "$base" "$sha"
  else
    printf '%s\n' "$s"
  fi
}

if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  base=$(basename "$git_root" | sanitize)
  sha=$(printf '%s' "$git_root" | shasum | cut -c1-8)
  emit "git-${base}-${sha}"
elif [ -n "${PWD:-}" ]; then
  emit "$(printf '%s' "$PWD" | sanitize)"
else
  emit "session-${CLAUDE_SESSION_ID:-unknown}"
fi
