# PetDesk Agent Guide

## Read First

Read `docs/product/petdesk-v1-spec.md`, `docs/architecture/overview.md`, and
`docs/architecture/state-machine.md` before changing behavior. Read the active plan in
`docs/superpowers/plans/` before implementation work. Read
`docs/development/git-workflow.md` before changing branches, committing, or publishing work.

## Architecture Rules

- Keep the project feature-first. A file owns one primary responsibility and is named after its primary type.
- Keep system APIs inside feature adapters. SwiftUI views must not sample CPU, query accessibility, or access files directly.
- Route behavior through `PetStateMachine`; do not add state-selection conditionals to views.
- Use Swift 6 strict concurrency. Do not add `@unchecked Sendable` without an ADR explaining the invariant.
- Do not use force unwraps in production code. Avoid generic names such as `Manager`, `Helper`, and `Utils`.
- Keep third-party runtime dependencies at zero unless an approved ADR changes this rule.

## Privacy Rules

- Never read, persist, or log message bodies, contact names, avatar paths, or imported filenames.
- Notification integration may inspect only the source application name through public Accessibility APIs.
- Do not add OCR, private notification databases, private frameworks, or SMC access.

## Workflow

1. Add a failing XCTest or `PetDeskCoreChecks` assertion for behavioral code and confirm the expected failure.
2. Implement the smallest change that passes it.
3. Run `make test`; before handoff run `make lint` and `make verify`.
4. Update architecture, debugging, and review docs when a contract or risk changes.
5. Use Conventional Commits and keep unrelated changes out of each commit.

Generated `PetDesk.xcodeproj` is never edited or committed. Change `project.yml`, then run `make generate`.

## Git Rules

- Run `git status --short --branch` before work and again before handoff.
- Never implement directly on `main`; use `feat/`, `fix/`, `refactor/`, `test/`, `docs/`, or `chore/` branches.
- Use Conventional Commits and keep each commit focused. Include the relevant tests and docs in the same commit.
- Run `make setup-git` once per clone. Do not bypass hooks unless the toolchain is unavailable and the skipped check is documented.
- Do not commit generated projects, build output, secrets, signing assets, or editor/user state.
- Never amend or rebase shared commits, force push, delete branches, or run destructive Git commands without explicit owner approval.
- Preserve unrelated and pre-existing user changes. Review `git diff --cached` before every commit.
- Follow `docs/development/git-workflow.md` for synchronization, pull requests, recovery, and release tags.
