# ADR 0001: XcodeGen Is the Project Source of Truth

## Status

Accepted on 2026-07-30.

## Decision

Commit `project.yml` and generate `PetDesk.xcodeproj` locally. Do not edit or commit the generated project.

## Consequences

Targets, deployment settings, entitlements, and schemes remain readable and mergeable for code agents. Contributors must install XcodeGen. SwiftPM provides a separate compile/test path but does not define the app bundle.
