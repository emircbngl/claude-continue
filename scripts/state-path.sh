#!/usr/bin/env bash
# Prints the state-id (directory name) for the current working dir.
# Fallback order: git-root > dash-encoded-cwd > session-id
# Length is hard-capped: long ids collapse to <prefix>-<truncated-base>-<hash>,
# where the hash source is the SAME path that defined the id (git root for git
# ids, cwd otherwise) — so every subdir of a repo maps to one state id.
set -euo pipefail

MAX_LEN=80

sanitize() { tr -c '[:alnum:]-_.' '-' | sed 's/--*/-/g; s/^-//; s/-$//'; }

emit() { # emit ID HASH_SOURCE_PATH PREFIX
  local s="$1" src="$2" prefix="$3"
  if [ "${#s}" -gt "$MAX_LEN" ]; then
    local base sha
    base=$(basename "$src" | sanitize | cut -c1-40)
    sha=$(printf '%s' "$src" | shasum | cut -c1-12)
    printf '%s-%s-%s\n' "$prefix" "$base" "$sha"
  else
    printf '%s\n' "$s"
  fi
}

if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  base=$(basename "$git_root" | sanitize)
  sha=$(printf '%s' "$git_root" | shasum | cut -c1-8)
  emit "git-${base}-${sha}" "$git_root" "git"
elif [ -n "${PWD:-}" ]; then
  emit "$(printf '%s' "$PWD" | sanitize)" "$PWD" "cwd"
else
  printf 'session-%s\n' "${CLAUDE_SESSION_ID:-unknown}" | cut -c1-"$MAX_LEN"
fi
