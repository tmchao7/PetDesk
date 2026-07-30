# Agent Handoff Protocol Design

## Purpose

PetDesk will be developed, debugged, and reviewed by multiple coding agents over time. The handoff protocol must let a newly started agent determine the current project state, trusted evidence, unfinished work, and next action without relying on chat history or undocumented memory.

The protocol is mandatory for implementation, debugging, review, research, and documentation sessions. It complements Git history, tests, plans, ADRs, and architecture documents; it does not replace them.

## Directory Model

```text
docs/agent-handoff/
├── README.md
├── CURRENT.md
├── TEMPLATE.md
└── sessions/
    └── YYYY-MM-DD-HHMM-<agent>-<task-slug>.md
```

`CURRENT.md` is the concise mutable entry point. It contains the active objective, current status, latest trusted verification, blockers, prioritized next actions, relevant commits, and a link to the newest session record. It must remain short enough for a new agent to read before inspecting code.

Each file under `sessions/` is an immutable record of one agent session. A new session creates a new file rather than appending to or rewriting an old file. Prior records may be corrected only when factually wrong; the correction must identify its author, date, and reason.

`TEMPLATE.md` defines required headings. `README.md` explains when and how to read, claim, update, validate, and commit a handoff.

## Session Lifecycle

At the start of every session, the agent must:

1. Read `AGENTS.md` and its tool-specific entry file.
2. Read `docs/agent-handoff/CURRENT.md` and the latest linked session record.
3. Inspect `git status --short --branch`, recent commits, the active plan, and relevant architecture or debugging documents.
4. Confirm that the stated objective is still compatible with the repository state before editing.

During work, the agent records durable decisions in the appropriate ADR, architecture, plan, or debugging document. The handoff may link to those documents but must not become a competing source of truth.

Before ending a session, including a no-code review or blocked attempt, the agent must:

1. Run verification appropriate to the work and record exact commands, exit status, and skipped checks.
2. Create a new session record from `TEMPLATE.md`.
3. Update `CURRENT.md` with the repository's actual state and prioritized next actions.
4. Run the handoff validator.
5. Commit the handoff with the related work or as a focused `docs(handoff)` commit.

An agent must not claim completion when required checks were skipped or failed. A blocked session must state the blocking condition, evidence already collected, unsuccessful approaches, and the smallest action that can unblock the next agent.

## Required Session Fields

Every session record contains:

- Metadata: timestamp with timezone, agent name, role, objective, branch, starting commit, ending commit or `uncommitted`.
- Context read: the plans, handoff records, architecture documents, issues, or review feedback consulted.
- Work performed: behavior changed, files changed, and investigation performed.
- Decisions: decisions made, rationale, rejected alternatives, and links to ADRs where applicable.
- Verification: exact commands, results, failure counts, and explicit skipped checks with reasons.
- Review and debug findings: severity, affected files or symbols, reproduction evidence, and status.
- Open issues and risks: confirmed gaps only, separated from speculation.
- Next actions: ordered, concrete steps with expected completion evidence.
- Git state: branch, commits created, staged or unstaged work, ignored artifacts, and remote or PR state.

The record must not include secrets, credentials, private message content, personal file paths beyond repository paths, or large copied logs. Store only the smallest diagnostic excerpt required to understand a finding.

## Status Vocabulary

`CURRENT.md` and session records use one of four explicit states:

- `ready`: the next action is known and no external blocker exists.
- `in_progress`: work has started and the owning agent is identified.
- `blocked`: progress requires a named external action or missing authority.
- `complete`: the stated objective and its required verification are finished.

The protocol does not use vague states such as `mostly done`, `looks good`, or `should pass`.

## Tooling

`scripts/new-agent-handoff.sh <agent> <task-slug>` creates a timestamped session file from the template and inserts repository metadata without overwriting an existing record. `make handoff-new AGENT=<agent> TASK=<task-slug>` exposes it through the standard command surface.

`scripts/check-agent-handoff.sh` verifies that `CURRENT.md` exists, links to an existing latest session, uses an allowed status, and that the latest session contains all required headings. `make handoff-check` runs this validator, and `make verify` includes it so pre-push validation enforces the protocol.

The generator does not invent work summaries, decisions, verification results, or next actions. Those fields must be filled by the agent responsible for the session.

## Concurrency and Conflict Handling

The protocol assumes sequential handoff but remains safe when agents overlap. Separate session files avoid history conflicts. Before updating `CURRENT.md`, an agent must re-read it and inspect Git status. If another agent changed it, preserve both agents' verified results, link both session records when relevant, and reconcile next actions rather than overwriting newer facts.

`CURRENT.md` never acts as a lock. An `in_progress` owner indicates intent, not exclusive ownership. Git branches and explicit task scope remain the mechanisms for isolating simultaneous changes.

## Global Enforcement

`AGENTS.md` will define the complete mandatory protocol. `CLAUDE.md` and `AGENT.md` will explicitly require reading `CURRENT.md` before work and writing a session record before handoff. `CONTRIBUTING.md`, the Git workflow, review checklist, and pull request template will link to the protocol.

The initial handoff record will document the repository state at the time this protocol is introduced, including the existing Xcode verification limitation. Future agents must update the records rather than treating the initial snapshot as permanent truth.

## Acceptance Criteria

- A new agent can identify the active branch, current objective, latest verification, known blocker, and next action by reading `CURRENT.md` and one linked session file.
- Two sequential agents never need to edit the same historical session record.
- Missing required headings, invalid status, or a broken latest-session link causes `make handoff-check` and `make verify` to fail.
- Agent entry documents describe start-of-session and end-of-session duties without contradicting the Git workflow.
- The initial record contains factual repository and verification state and no placeholders.
