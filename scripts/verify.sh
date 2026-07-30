#!/bin/zsh
set -euo pipefail

zsh scripts/tests/agent-handoff-tests.sh
zsh scripts/check-agent-handoff.sh
swift package dump-package >/dev/null
swift format lint --recursive PetDesk Checks PetDeskTests PetDeskUITests
swift build --product PetDeskAppCheck
swift run PetDeskCoreChecks
plutil -lint Config/PetDesk.entitlements

if rg -n '@unchecked Sendable|try!|as!|fatalError\(' PetDesk; then
  echo "Forbidden Swift construct found." >&2
  exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --spec project.yml >/dev/null
else
  echo "NOTE: XcodeGen is unavailable; project generation was not checked."
fi

if xcodebuild -version >/dev/null 2>&1; then
  zsh scripts/check-xcode-target-identities.sh
  xcodebuild \
    -project PetDesk.xcodeproj \
    -scheme PetDesk \
    -configuration Debug \
    build \
    CODE_SIGNING_ALLOWED=NO
  xcodebuild \
    -project PetDesk.xcodeproj \
    -scheme PetDesk \
    test
else
  echo "NOTE: Full Xcode is unavailable; app-bundle build, XCTest, and XCUITest were skipped."
fi

echo "PetDesk verification completed."
