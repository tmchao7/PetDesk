# PetDesk

PetDesk is a native macOS 26 desktop companion. It animates an imported avatar in response to CPU load, coarse thermal pressure, user activity, focus sessions, and optional best-effort WeChat/QQ notification pulses.

## Requirements

- Apple silicon Mac running macOS 26
- Xcode 26 with its developer directory selected
- XcodeGen (`brew install xcodegen`)

## Development

```bash
make setup-git
make bootstrap
make generate
make test
make run
```

The generated Xcode project is local output. `project.yml` is the reviewed project definition. The Swift package exists to test the non-UI core without generating an app bundle.

## Contributing

Repository rules are documented in `CONTRIBUTING.md`. Branch naming, Conventional Commits, hooks, pull requests, recovery, and release tagging are defined in `docs/development/git-workflow.md`. Coding agents must also follow `AGENTS.md` and their tool-specific entry file.

## Privacy

All state stays on the Mac. PetDesk does not read notification bodies or contact names. The optional notification experiment inspects only a notification's source app and degrades to unsupported when the Accessibility tree is not usable.
