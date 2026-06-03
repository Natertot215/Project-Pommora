#!/usr/bin/env bash
# MarkdownPM characterization gate. Runs BOTH the package-own suites
# (swift test) and the app-side public-surface + on-disk suites
# (xcodebuild test -scheme Pommora -only-testing:PommoraTests).
# Exits non-zero if EITHER leg fails.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="$REPO_ROOT/External/MarkdownPM"

echo "== MarkdownPM package suites (swift test) =="
swift test --package-path "$PKG_PATH" \
  -Xswiftc -sdk -Xswiftc "$(xcrun --sdk macosx --show-sdk-path)"

echo "== App-side suites (xcodebuild test -only-testing:PommoraTests) =="
xcodebuild test \
  -project "$REPO_ROOT/Pommora/Pommora.xcodeproj" \
  -scheme Pommora \
  -destination 'platform=macOS' \
  -only-testing:PommoraTests
