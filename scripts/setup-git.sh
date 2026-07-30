#!/bin/zsh
set -euo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Run this command inside the PetDesk Git repository." >&2
  exit 1
}

cd "$root"
git config --local core.hooksPath .githooks
git config --local pull.ff only
git config --local fetch.prune true
git config --local commit.cleanup strip

echo "Git repository settings installed:"
echo "  core.hooksPath=$(git config --local core.hooksPath)"
echo "  pull.ff=$(git config --local pull.ff)"
echo "  fetch.prune=$(git config --local fetch.prune)"
