# Claude Code Entry Point

Read and follow `AGENTS.md`. Then read the active plan under `docs/superpowers/plans/` and the architecture documents it references. `AGENTS.md` is the canonical rule set; do not duplicate or override it here.

## Git Requirements

Before editing, run `git status --short --branch` and confirm the branch is not `main`. Read `docs/development/git-workflow.md`, keep unrelated changes intact, use Conventional Commits, and inspect the staged diff before committing. Do not amend shared commits, force push, delete branches, bypass hooks, or use destructive Git commands without explicit owner approval. Run `make verify` before handoff.
