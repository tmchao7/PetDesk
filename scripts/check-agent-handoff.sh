#!/bin/zsh
set -u

fail() {
  echo "Agent handoff validation failed: $1" >&2
  exit 1
}

if (( $# > 1 )); then
  fail "Usage: scripts/check-agent-handoff.sh [repository-root]"
fi

if (( $# == 1 )); then
  repository_root=$1
else
  repository_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "Not inside a Git repository"
fi

handoff_root="$repository_root/docs/agent-handoff"
current_file="$handoff_root/CURRENT.md"
[[ -f "$current_file" ]] || fail "Missing CURRENT.md"

handoff_status=$(sed -nE 's/^- Status: ([a-z_]+)$/\1/p' "$current_file" | head -n 1)
case "$handoff_status" in
  ready | in_progress | blocked | complete) ;;
  *) fail "Invalid handoff status: ${handoff_status:-missing}" ;;
esac

latest_session=$(sed -nE 's/^- Latest session: \[[^]]+\]\(([^)]+)\)$/\1/p' "$current_file" | head -n 1)
[[ -n "$latest_session" ]] || fail "Missing latest session link"
[[ "$latest_session" == sessions/*.md ]] || fail "Invalid latest session path: $latest_session"
[[ "$latest_session" != *".."* && "$latest_session" != /* ]] || fail "Invalid latest session path: $latest_session"

session_file="$handoff_root/$latest_session"
[[ -f "$session_file" ]] || fail "Latest session does not exist: $latest_session"

required_headings=(
  "## Metadata"
  "## Context Read"
  "## Work Performed"
  "## Decisions"
  "## Verification"
  "## Review and Debug Findings"
  "## Open Issues and Risks"
  "## Next Actions"
  "## Git State"
)

for heading in "${required_headings[@]}"; do
  rg -F -x -q "$heading" "$session_file" || fail "Missing required heading: $heading"
done

if rg -n -q 'REPLACE_ME' "$current_file" "$session_file"; then
  fail "Unfinished REPLACE_ME token found"
fi

echo "Agent handoff validation passed: $latest_session"
