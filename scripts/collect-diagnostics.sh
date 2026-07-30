#!/bin/zsh
set -euo pipefail

log show \
  --last "${1:-10m}" \
  --style compact \
  --predicate 'subsystem == "io.github.tmchao7.PetDesk"'
