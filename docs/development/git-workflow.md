# Git Workflow

This document is the Git source of truth for people and coding agents working on PetDesk.

## One-Time Setup

Run the repository setup after cloning:

```bash
make setup-git
```

This selects the tracked hooks directory, requires fast-forward-only pulls, and prunes deleted remote branches during fetch. Add a remote only when the GitHub repository exists:

```bash
git remote add origin <repository-url>
git push -u origin main
```

## Branch Model

`main` must remain reviewable and releasable. Do not implement directly on `main`. Create a short-lived branch using one of these prefixes:

- `feat/` for user-facing capability
- `fix/` for defects
- `refactor/` for behavior-preserving restructuring
- `test/` for test-only changes
- `docs/` for documentation-only changes
- `chore/` for tooling and repository maintenance

Start work with:

```bash
git status --short --branch
git switch main
git pull --ff-only
git switch -c feat/short-description
```

Keep unrelated user changes intact. Never use `git reset --hard`, `git clean -fd`, `git checkout -- <path>`, or force push unless the owner explicitly authorizes the exact destructive action.

## Commits

Use Conventional Commits: `type(scope): imperative summary`. The scope is optional; useful examples are `pet-domain`, `window`, `avatar`, `focus`, `docs`, and `build`.

```text
feat(focus): add idle-aware session pause
fix(window): clamp pet after display removal
docs(git): document review workflow
chore(build): update XcodeGen settings
```

Each commit must represent one coherent change, include its tests and documentation, and pass the configured pre-commit hook. Do not commit `.build/`, `DerivedData/`, generated `PetDesk.xcodeproj`, secrets, signing material, or user-specific Xcode data.

Agent work must also satisfy `docs/agent-handoff/README.md`. A handoff record may be included with its coherent implementation commit. When it must refer to the final implementation commit hash, create a focused follow-up commit such as `docs(handoff): record mimocode debug review`.

Do not amend, rebase, or otherwise rewrite commits that may have been shared. A private branch may be rebased onto `origin/main`; use a normal merge when other people or agents already consume the branch.

## Review and Integration

Before opening a pull request:

```bash
make verify
make handoff-check
git status --short
git log --oneline main..HEAD
git diff --stat main...HEAD
```

The pull request must describe behavior, verification evidence, privacy or permission impact, documentation changes, and any Xcode-only checks that could not run. Prefer squash merge for a noisy development branch and regular merge when the individual commits form useful project history.

Tag releases only from verified `main` using annotated semantic-version tags such as `v0.1.0`. Never tag a feature branch.

## Hooks

The pre-commit hook rejects whitespace errors, lints staged Swift files, and runs core checks when Swift or project definitions change. The pre-push hook runs `make verify`. Bypass hooks only for a documented toolchain outage, and record the missing check in the commit or pull request.

Use `git reflog` before attempting recovery from an accidental branch move. Ask the repository owner before deleting branches or discarding uncommitted work.
