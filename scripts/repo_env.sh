#!/usr/bin/env bash
set -euo pipefail

# SolMobile repo environment hook.
#
# This is intentionally conservative: it does not install anything.
# It only verifies that Xcode tooling is present and optionally pins DEVELOPER_DIR.

use_repo_env() {
  local root="${1:-.}"
  cd "$root" || return 1

  if [[ "$(uname)" != "Darwin" ]]; then
    echo "BREAKPOINT: SolMobile gates require macOS (xcodebuild)."
    return 2
  fi

  # Optional pinning: export XCODE_DEVELOPER_DIR in your shell if you need a specific Xcode.
  if [[ -n "${XCODE_DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
  fi

  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "BREAKPOINT: xcodebuild not found. Install Xcode or Command Line Tools."
    return 2
  fi

  # Cleaner logs for some Swift tools.
  export NSUnbufferedIO=YES
}

export -f use_repo_env
