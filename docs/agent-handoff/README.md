# Agent Handoff Protocol

This directory is the mandatory relay point for every coding agent that implements, debugs, reviews, researches, or documents PetDesk.

## Sources of Truth

- `CURRENT.md` answers what is happening now and what should happen next.
- The session linked from `CURRENT.md` provides evidence and detailed history for the latest handoff.
- Older files under `sessions/` are immutable history.
- Product specs, plans, ADRs, architecture docs, tests, commits, issues, and pull requests remain authoritative for their own concerns. Do not duplicate them here; link them.

## Start of Session

Before editing anything:

1. Read `AGENTS.md` and the tool-specific `CLAUDE.md` or `AGENT.md` entry point.
2. Read `CURRENT.md` and its latest linked session.
3. Run `git status --short --branch` and inspect recent commits.
4. Read the active plan and relevant architecture, debugging, review, or issue context.
5. Confirm that the requested work still matches repository state. Preserve unrelated user or agent changes.

Do not treat `CURRENT.md` as a lock. Branches and explicit scope isolate simultaneous work. Re-read `CURRENT.md` before updating it so newer verified facts are not overwritten.

## End of Session

Every session must leave a handoff, including sessions that are blocked, review-only, debug-only, or produce no code changes.

1. Run verification appropriate to the work. Record exact commands, results, and skipped checks.
2. Generate a record with `make handoff-new AGENT=<agent> TASK=<task-slug>` or copy `TEMPLATE.md` manually.
3. Replace every `REPLACE_ME` token with factual information.
4. Update `CURRENT.md`, keeping it concise and linking the new session.
5. Run `make handoff-check` and `make verify` when code or tooling changed.
6. Commit the record with the related work or in a focused `docs(handoff)` commit.

Do not claim completion when a required check failed or was skipped. Use only these states:

- `ready`: a concrete next action exists and no external blocker prevents it.
- `in_progress`: partially completed work is being handed off with an identified owner.
- `blocked`: a named external action or missing authority prevents progress.
- `complete`: the stated objective and required verification are finished.

## Session Records

Session filenames use `YYYY-MM-DD-HHMM-<agent>-<task-slug>.md`. Never overwrite or append to an older session. A factual correction to an older record must add the correcting agent, date, and reason without removing the original statement.

Record repository-relative paths, concise diagnostic excerpts, and links to durable decisions. Never include credentials, secrets, private message content, contact data, imported filenames, or unrelated personal paths.

## Commands

```bash
make handoff-new AGENT=mimocode TASK=debug-review
make handoff-check
make handoff-test
```

The generator supplies timestamp, agent, objective, branch, and starting commit. The responsible agent must still fill role, work, decisions, verification, risks, next actions, ending commit, and Git state.
