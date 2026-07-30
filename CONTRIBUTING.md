# Contributing to PetDesk

Read `AGENTS.md` for architecture, privacy, testing, and agent constraints. Read `docs/development/git-workflow.md` before creating a branch or commit.

## Local Setup

```bash
make setup-git
make bootstrap
make verify
```

Use a prefixed feature branch, write behavioral tests before production changes, keep generated Xcode files untracked, and update the relevant architecture or debugging document when a contract changes.

Pull requests must use `.github/pull_request_template.md`. A change is reviewable only when its scope is coherent, verification evidence is recorded, and privacy-sensitive integrations remain within `SECURITY.md`.
