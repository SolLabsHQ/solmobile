#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "SolMobile bootstrap: FAIL (requires macOS / Xcode)"
  exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "SolMobile bootstrap: FAIL (xcodebuild not found)"
  echo "Install Xcode (or Command Line Tools) and ensure xcodebuild is on PATH."
  exit 2
fi

echo "SolMobile bootstrap: xcodebuild present ✅"
xcodebuild -version || true

# Optional: sanity check project/workspace presence (non-fatal).
ws="$(ls -1 *.xcworkspace 2>/dev/null | head -n1 || true)"
prj="$(ls -1 *.xcodeproj 2>/dev/null | head -n1 || true)"

if [[ -n "$ws" ]]; then
  echo "Found workspace: $ws"
  xcodebuild -workspace "$ws" -list >/dev/null || true
elif [[ -n "$prj" ]]; then
  echo "Found project: $prj"
  xcodebuild -project "$prj" -list >/dev/null || true
else
  echo "No .xcworkspace/.xcodeproj found at repo root (ok if nested)."
fi

echo "SolMobile bootstrap: ok ✅"
