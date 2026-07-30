#!/bin/zsh
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "Homebrew is required to install XcodeGen." >&2
    exit 1
  fi
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Install Xcode 26, then select it with:" >&2
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
  exit 2
fi

xcodegen generate --spec project.yml
echo "PetDesk toolchain is ready."
