# Agent Handoff Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a validated, Git-tracked handoff system that lets sequential coding agents recover project state and record implementation, debugging, and review work.

**Architecture:** `CURRENT.md` is the short mutable entry point while immutable timestamped files preserve session history. Shell tools create session records and validate status, links, required sections, and unfinished tokens; the repository verification command enforces the protocol.

**Tech Stack:** Markdown, zsh, Git, Make.

---

### Task 1: Define Validator Behavior Test-First

**Files:**
- Create: `scripts/tests/agent-handoff-tests.sh`
- Create: `scripts/check-agent-handoff.sh`

- [ ] **Step 1: Write the failing validator tests**

Create a temporary `docs/agent-handoff` fixture and assert five behaviors: missing `CURRENT.md` fails, invalid status fails, broken latest-session link fails, missing required session heading fails, and a complete fixture passes. Use a small `expect_failure` shell function that checks both nonzero exit status and a stable error substring.

- [ ] **Step 2: Run the tests and confirm RED**

Run: `zsh scripts/tests/agent-handoff-tests.sh`

Expected: nonzero exit because `scripts/check-agent-handoff.sh` does not exist.

- [ ] **Step 3: Implement the validator**

Implement `scripts/check-agent-handoff.sh [repository-root]`. Default the root to `git rev-parse --show-toplevel`; validate an allowed `Status` value, extract the Markdown target from `Latest session`, reject absolute or parent-traversing paths, require the target file, require all nine session headings, and reject `REPLACE_ME` in the latest record or `CURRENT.md`.

- [ ] **Step 4: Run the tests and confirm GREEN**

Run: `zsh scripts/tests/agent-handoff-tests.sh`

Expected: `Agent handoff tests: all checks passed` and exit 0.

### Task 2: Create the Handoff Documents and Generator

**Files:**
- Create: `docs/agent-handoff/README.md`
- Create: `docs/agent-handoff/CURRENT.md`
- Create: `docs/agent-handoff/TEMPLATE.md`
- Create: `docs/agent-handoff/sessions/<timestamp>-codex-agent-handoff-protocol.md`
- Create: `scripts/new-agent-handoff.sh`
- Modify: `scripts/tests/agent-handoff-tests.sh`

- [ ] **Step 1: Extend tests for generator behavior**

In a temporary Git repository, copy the template, run `scripts/new-agent-handoff.sh mimocode debug-review`, and assert that exactly one timestamped file exists with agent, branch, starting commit, objective, and all required headings. Run it again in the same minute and assert it refuses to overwrite the first file.

- [ ] **Step 2: Run generator tests and confirm RED**

Run: `zsh scripts/tests/agent-handoff-tests.sh`

Expected: nonzero exit because `scripts/new-agent-handoff.sh` does not exist.

- [ ] **Step 3: Write protocol docs and generator**

Write the lifecycle and source-of-truth rules from the approved design into `README.md`. Make `TEMPLATE.md` contain the exact required headings and `REPLACE_ME` tokens only where the responsible agent must write evidence. The generator accepts `<agent> <task-slug>`, validates lowercase safe identifiers, copies the template, replaces metadata tokens, and refuses collisions. Create an initial factual session record and a concise `CURRENT.md` linking it.

- [ ] **Step 4: Run tests and validator**

Run: `zsh scripts/tests/agent-handoff-tests.sh && zsh scripts/check-agent-handoff.sh`

Expected: both commands exit 0 without unfinished tokens in the initial live record.

### Task 3: Enforce the Protocol Globally

**Files:**
- Modify: `Makefile`
- Modify: `scripts/verify.sh`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `AGENT.md`
- Modify: `CONTRIBUTING.md`
- Modify: `README.md`
- Modify: `docs/development/git-workflow.md`
- Modify: `docs/review/checklist.md`
- Modify: `.github/pull_request_template.md`

- [ ] **Step 1: Add command integration**

Add `handoff-new`, `handoff-check`, and `handoff-test` Make targets. Require `AGENT` and `TASK` for generation. Run `handoff-test` and `handoff-check` near the start of `scripts/verify.sh` before the expensive Swift build.

- [ ] **Step 2: Add mandatory start/end duties**

Make `AGENTS.md` the canonical protocol: every agent reads `CURRENT.md` plus the latest session before editing, rechecks it before handoff, creates a new session for code, debug, review, research, or blocked work, updates `CURRENT.md`, runs validation, and commits the record. Add concise explicit versions to `CLAUDE.md` and `AGENT.md`.

- [ ] **Step 3: Link human workflow surfaces**

Add the protocol to onboarding, Git workflow, review checklist, and PR checklist. State that handoffs complement rather than replace tests, ADRs, plans, issues, commits, or PR descriptions.

- [ ] **Step 4: Verify documentation consistency**

Run: `rg -n 'agent-handoff|handoff-(new|check|test)' AGENTS.md CLAUDE.md AGENT.md CONTRIBUTING.md README.md Makefile scripts/verify.sh docs/development/git-workflow.md docs/review/checklist.md .github/pull_request_template.md`

Expected: every required entry surface references the protocol or command without contradictory paths.

### Task 4: Record This Session and Commit

**Files:**
- Update: `docs/agent-handoff/CURRENT.md`
- Update: the new session record under `docs/agent-handoff/sessions/`
- Update: `docs/superpowers/plans/2026-07-30-agent-handoff.md`

- [ ] **Step 1: Fill factual handoff evidence**

Record the approved design and plan commits, files created or modified, exact verification output, the full-Xcode limitation, current remote/upstream state, and concrete next actions for MimoCode. Mark completed plan boxes accurately.

- [ ] **Step 2: Run full verification**

Run: `make verify`

Expected: handoff tests and validator pass, core checks pass, entitlements lint passes, and the existing full-Xcode skip is reported explicitly.

- [ ] **Step 3: Review and commit**

Run: `git diff --check`, `git diff --cached --check`, and `git status --short --branch`. Commit the coherent protocol implementation with `docs(handoff): add multi-agent relay system`. Do not push.
