#!/usr/bin/env bash
set -euo pipefail
source scripts/_lib.sh

load_packet
cd "$REPO_ROOT"

PR_URL_OR_NUM="${SOLMOBILE_PR:-}"
REPO_SLUG="${REPO_SLUG:-}"

out_dir="$RECEIPTS_DIR"
body_file="$out_dir/pr_body_solmobile.md"

cat > "$body_file" <<'EOF'
## Why
TBD

## What changed
* [x] TBD

## Risk
* Risk level: TBD (Low/Medium/High)
* Failure modes:
  * TBD
* Rollback plan: TBD

## Checks
* [x] No secrets added
* [x] Main remains PR-only

## Links
Issue: TBD
ADR: TBD
Docs: TBD
Follow-ups: TBD

### Connected PRs
infra-docs: TBD
solserver:  TBD
solmobile:  TBD

### Staging Merge Gate
TBD

### Test Results
- TBD
EOF

if [[ -f "$CHECKLIST_PATH" ]]; then
  echo "" >> "$body_file"
  echo "#### Gate receipts (from checklist)" >> "$body_file"
  grep -E "unit \(AUTO\)|lint \(AUTO\)|integration \(AUTO\)|snapshot \(AUTO\)" "$CHECKLIST_PATH" >> "$body_file" || true
fi

echo "Generated: $body_file"

if command -v gh >/dev/null 2>&1 && [[ -n "$PR_URL_OR_NUM" ]]; then
  echo "Applying via gh pr edit..."
  if [[ -n "$REPO_SLUG" ]]; then
    gh pr edit "$PR_URL_OR_NUM" -R "$REPO_SLUG" --body-file "$body_file"
  else
    gh pr edit "$PR_URL_OR_NUM" --body-file "$body_file"
  fi
  echo "Applied PR body."
else
  echo "Not applied. Set SOLMOBILE_PR=<PR url|num> and ensure gh auth to apply automatically."
fi
