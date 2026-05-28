#!/usr/bin/env bash
# Prints ATTENDED if stdin/stdout are TTYs (interactive session), else UNATTENDED.
if [ -t 0 ] && [ -t 1 ]; then
  echo "ATTENDED"
else
  echo "UNATTENDED"
fi
