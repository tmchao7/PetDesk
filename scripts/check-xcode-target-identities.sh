#!/bin/zsh
set -euo pipefail

project=${1:-PetDesk.xcodeproj}
targets=(PetDesk PetDeskTests PetDeskUITests)

for target in ${targets[@]}; do
  settings=$(xcodebuild \
    -project "$project" \
    -target "$target" \
    -configuration Debug \
    -showBuildSettings 2>/dev/null)
  product_name=$(awk -F ' = ' '/^[[:space:]]*PRODUCT_NAME = / { print $2; exit }' <<<"$settings")
  module_name=$(awk -F ' = ' '/^[[:space:]]*PRODUCT_MODULE_NAME = / { print $2; exit }' <<<"$settings")

  if [[ "$product_name" != "$target" ]]; then
    echo "Target $target resolves PRODUCT_NAME to '$product_name'; expected '$target'." >&2
    exit 1
  fi
  if [[ "$module_name" != "$target" ]]; then
    echo "Target $target resolves PRODUCT_MODULE_NAME to '$module_name'; expected '$target'." >&2
    exit 1
  fi
done

echo "Xcode target identity validation passed."
