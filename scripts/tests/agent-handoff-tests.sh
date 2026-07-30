#!/bin/zsh
set -u

repo_root=$(git rev-parse --show-toplevel)
validator="$repo_root/scripts/check-agent-handoff.sh"
generator="$repo_root/scripts/new-agent-handoff.sh"
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/petdesk-handoff-tests.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT

fail() {
  echo "Agent handoff tests: $1" >&2
  exit 1
}

expect_failure() {
  local expected=$1
  shift
  local output
  output=$("$@" 2>&1)
  local exit_code=$?
  (( exit_code != 0 )) || fail "expected command to fail: $*"
  [[ "$output" == *"$expected"* ]] || fail "expected failure containing '$expected', got: $output"
}

expect_success() {
  local output
  output=$("$@" 2>&1)
  local exit_code=$?
  (( exit_code == 0 )) || fail "expected command to pass, got: $output"
}

write_valid_fixture() {
  local root=$1
  rm -rf "$root"
  mkdir -p "$root/docs/agent-handoff/sessions"
  cat >"$root/docs/agent-handoff/CURRENT.md" <<'EOF'
# Current Agent Handoff

- Status: ready
- Latest session: [test-session](sessions/test-session.md)

## Active Objective

Validate the handoff protocol.
EOF

  cat >"$root/docs/agent-handoff/sessions/test-session.md" <<'EOF'
# Agent Session Handoff

## Metadata
Complete metadata.

## Context Read
Complete context.

## Work Performed
Complete work.

## Decisions
Complete decisions.

## Verification
Complete verification.

## Review and Debug Findings
No findings.

## Open Issues and Risks
No open issues.

## Next Actions
Run the validator.

## Git State
Clean fixture.
EOF
}

case_root="$fixture_root/case"

write_valid_fixture "$case_root"
rm "$case_root/docs/agent-handoff/CURRENT.md"
expect_failure "Missing CURRENT.md" "$validator" "$case_root"

write_valid_fixture "$case_root"
perl -0pi -e 's/Status: ready/Status: uncertain/' "$case_root/docs/agent-handoff/CURRENT.md"
expect_failure "Invalid handoff status" "$validator" "$case_root"

write_valid_fixture "$case_root"
perl -0pi -e 's/test-session\.md/missing-session.md/' "$case_root/docs/agent-handoff/CURRENT.md"
expect_failure "Latest session does not exist" "$validator" "$case_root"

write_valid_fixture "$case_root"
perl -0pi -e 's/## Verification\nComplete verification\.\n\n//' "$case_root/docs/agent-handoff/sessions/test-session.md"
expect_failure "Missing required heading: ## Verification" "$validator" "$case_root"

write_valid_fixture "$case_root"
expect_success "$validator" "$case_root"

generator_root="$fixture_root/generator"
mkdir -p "$generator_root/docs/agent-handoff/sessions"
cat >"$generator_root/docs/agent-handoff/TEMPLATE.md" <<'EOF'
# Agent Session Handoff

## Metadata

- Timestamp: {{TIMESTAMP}}
- Agent: {{AGENT}}
- Role: {{ROLE}}
- Objective: {{OBJECTIVE}}
- Branch: {{BRANCH}}
- Starting commit: {{START_COMMIT}}
- Ending commit: uncommitted

## Context Read
REPLACE_ME

## Work Performed
REPLACE_ME

## Decisions
REPLACE_ME

## Verification
REPLACE_ME

## Review and Debug Findings
REPLACE_ME

## Open Issues and Risks
REPLACE_ME

## Next Actions
REPLACE_ME

## Git State
REPLACE_ME
EOF

git -C "$generator_root" init -q -b feat/test-handoff
git -C "$generator_root" config user.name "PetDesk Test"
git -C "$generator_root" config user.email "petdesk-test@example.invalid"
git -C "$generator_root" add .
git -C "$generator_root" commit -q -m "test: initialize fixture"

run_generator() {
  (cd "$generator_root" && "$generator" mimocode debug-review)
}

expect_success run_generator
generated_files=("$generator_root"/docs/agent-handoff/sessions/*.md)
(( ${#generated_files[@]} == 1 )) || fail "expected one generated session file"
generated_file=${generated_files[1]}
rg -q '^- Agent: mimocode$' "$generated_file" || fail "generated agent metadata is missing"
rg -q '^- Objective: debug review$' "$generated_file" || fail "generated objective metadata is missing"
rg -q '^- Branch: feat/test-handoff$' "$generated_file" || fail "generated branch metadata is missing"
rg -q "^- Starting commit: $(git -C "$generator_root" rev-parse --short HEAD)$" "$generated_file" || fail "generated commit metadata is missing"
generated_headings=(
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
for heading in "${generated_headings[@]}"; do
  rg -F -x -q "$heading" "$generated_file" || fail "generated file is missing heading: $heading"
done
expect_failure "already exists" run_generator

echo "Agent handoff tests: all checks passed"
