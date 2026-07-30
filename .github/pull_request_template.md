## Summary

- Describe the user-visible or engineering outcome.
- Explain why this change belongs in PetDesk.

## Verification

- [ ] `make lint`
- [ ] `make test`
- [ ] `make verify`
- [ ] `make handoff-check`
- [ ] Xcode app build and relevant XCUITest, or the missing Xcode-only check is documented below

## Review Checklist

- [ ] The branch contains one coherent change and uses Conventional Commits.
- [ ] Generated Xcode files, local state, signing files, and secrets are not committed.
- [ ] Behavioral changes have tests and documentation changes are included.
- [ ] Logs and diagnostics contain no message content, contacts, filenames, or private paths.
- [ ] New permissions or system integrations are described in `SECURITY.md`.
- [ ] `docs/agent-handoff/CURRENT.md` links the latest complete session record.

## Known Gaps

State any unrun checks, compatibility limits, or follow-up work. Write `None` when there are no known gaps.
