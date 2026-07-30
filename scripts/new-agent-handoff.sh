#!/bin/zsh
set -euo pipefail

usage() {
  echo "Usage: scripts/new-agent-handoff.sh <agent> <task-slug>" >&2
  exit 1
}

(( $# == 2 )) || usage
agent=$1
task_slug=$2

[[ "$agent" =~ '^[a-z0-9][a-z0-9-]*$' ]] || {
  echo "Agent must use lowercase letters, numbers, and hyphens." >&2
  exit 1
}
[[ "$task_slug" =~ '^[a-z0-9][a-z0-9-]*$' ]] || {
  echo "Task slug must use lowercase letters, numbers, and hyphens." >&2
  exit 1
}

repository_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Run this command inside the PetDesk Git repository." >&2
  exit 1
}
template="$repository_root/docs/agent-handoff/TEMPLATE.md"
sessions="$repository_root/docs/agent-handoff/sessions"
[[ -f "$template" ]] || {
  echo "Missing handoff template: $template" >&2
  exit 1
}

timestamp_file=$(date '+%Y-%m-%d-%H%M')
timestamp_value=$(date '+%Y-%m-%dT%H:%M:%S%z')
branch=$(git -C "$repository_root" branch --show-current)
[[ -n "$branch" ]] || branch="detached-head"
starting_commit=$(git -C "$repository_root" rev-parse --short HEAD)
objective=${task_slug//-/ }
target="$sessions/$timestamp_file-$agent-$task_slug.md"

mkdir -p "$sessions"
[[ ! -e "$target" ]] || {
  echo "Handoff session already exists: ${target#$repository_root/}" >&2
  exit 1
}

sed \
  -e "s|{{TIMESTAMP}}|$timestamp_value|g" \
  -e "s|{{AGENT}}|$agent|g" \
  -e "s|{{OBJECTIVE}}|$objective|g" \
  -e "s|{{BRANCH}}|$branch|g" \
  -e "s|{{START_COMMIT}}|$starting_commit|g" \
  "$template" >"$target"

echo "Created ${target#$repository_root/}"
