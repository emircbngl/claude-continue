#!/usr/bin/env bash
# Prints ATTENDED or UNATTENDED.
# A TTY test is useless here: hooks receive JSON on a stdin pipe and the Bash
# tool also runs without a TTY, so [ -t 0 ] would report UNATTENDED even when
# the user is right there. The reliable signal is explicit: the launchd job
# (the only truly unattended entry point) sets CLAUDE_CONTINUE_UNATTENDED=1
# in the command it types into the terminal. Everything else is attended —
# if the user typed /awake, the user is present.
if [ "${CLAUDE_CONTINUE_UNATTENDED:-0}" = "1" ]; then
  echo "UNATTENDED"
else
  echo "ATTENDED"
fi
