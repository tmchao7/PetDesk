# Contributing to PetDesk

Read `AGENTS.md` for architecture, privacy, testing, and agent constraints. Read `docs/development/git-workflow.md` before creating a branch or commit. Coding agents must also read `docs/agent-handoff/CURRENT.md` and the latest linked session before starting work.

## Local Setup

```bash
make setup-git
make bootstrap
make verify
```

Use a prefixed feature branch, write behavioral tests before production changes, keep generated Xcode files untracked, and update the relevant architecture or debugging document when a contract changes.

Before handing work to another person or agent, follow `docs/agent-handoff/README.md`, create a new session record, update `CURRENT.md`, and run `make handoff-check`. This requirement also applies to review-only, debug-only, and blocked sessions.

Pull requests must use `.github/pull_request_template.md`. A change is reviewable only when its scope is coherent, verification evidence is recorded, and privacy-sensitive integrations remain within `SECURITY.md`.
