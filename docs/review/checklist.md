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
- `make verify` passes; Xcode-only checks are explicitly reported if unavailable.
