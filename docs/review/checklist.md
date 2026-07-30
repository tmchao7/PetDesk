# Review Checklist

- Behavior changes enter through `PetEvent` and have reducer tests.
- Views contain no hardware sampling, file reads, or Accessibility traversal.
- Tasks are cancelled and repeated `start()` calls cannot duplicate monitors.
- CPU math handles first sample, zero delta, and rollback.
- Window coordinates are clamped after display changes.
- Imported images are validated and downsampled before persistence.
- Logs and diagnostics contain no paths, filenames, contacts, or message contents.
- No force unwrap, `try!`, `as!`, `fatalError`, or unexplained `@unchecked Sendable` exists.
- `project.yml`, docs, and tests change with interface changes.
- Shared `.xcconfig` files do not define target product names, bundle identifiers, or app-only runtime settings.
- `make verify` passes; Xcode-only checks are explicitly reported if unavailable.
- The branch is not `main`, commits are scoped and conventional, and generated or local files remain untracked.
- `git diff --cached --check` passes and the staged diff contains no unrelated user changes.
- `CURRENT.md` links the newest agent session, the record has exact verification evidence, and `make handoff-check` passes.
- Review-only and debug-only sessions record findings and next actions even when no production file changes.
