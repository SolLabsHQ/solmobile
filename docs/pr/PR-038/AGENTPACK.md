# AGENTPACK — PR-038 — SOLM-EPIC-043

## Packet files
- INPUT: ./INPUT.md
- CHECKLIST: ./CHECKLIST.md
- FIXLOG: ./FIXLOG.md

## Gates
- unit: xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj
- lint: xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj
- integration: xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj

<!-- BEGIN GENERATED: canonical-spec-anchor -->
## Canonical Spec Anchor (infra-docs)
- Epic: SOLM-EPIC-043
- Canonical repo: SolLabsHQ/infra-docs
- Canonical commit: c9e113b487b18b658db19bf145632945ba0e613c
- Canonical epic path: codex/epics/SOLM-EPIC-043/
- Canonical files:
  - decisions/ADR-031-threadmemento-v0.2-breakpointengine-context-thread-memento-peak-guardrail.md (https://github.com/SolLabsHQ/infra-docs/blob/c9e113b487b18b658db19bf145632945ba0e613c/decisions/ADR-031-threadmemento-v0.2-breakpointengine-context-thread-memento-peak-guardrail.md)
Notes:
- If you have a local checkout, set INFRA_DOCS_ROOT to verify locally.
- Otherwise CI will verify via GitHub at the pinned commit.
<!-- END GENERATED: canonical-spec-anchor -->

<!-- BEGIN GENERATED: epic-execution-payload -->
## Scope for solmobile
- code + tests for structured ThreadMemento persistence and precedence.

## Required Behaviors
- Prefer structured ThreadMemento payload for outbound send.
- Summary parse is fallback only.
- serverThreadMementoSummary is UI-only, not canonical.
- Malformed stored payload must not crash; log + fallback safely.
- Revoke/clear clears both stored representations.
- No API/schema version bump.

## Acceptance Criteria
- SolMobile unit tests for precedence + fallback + revoke clearing.
- Black-box two-turn carry test: stored_latest used on turn B when request memento omitted.

## Out of Scope
- infra-docs: update ADR-031 with Addendum A1 and create epic packet files.
- solserver: no contract changes; tests only.

## Packet Source Docs
- codex/epics/SOLM-EPIC-043/AGENTPACK-SOLM-EPIC-043.md (https://github.com/SolLabsHQ/infra-docs/blob/c9e113b487b18b658db19bf145632945ba0e613c/codex/epics/SOLM-EPIC-043/AGENTPACK-SOLM-EPIC-043.md)
- codex/epics/SOLM-EPIC-043/INPUT-SOLM-EPIC-043.md (https://github.com/SolLabsHQ/infra-docs/blob/c9e113b487b18b658db19bf145632945ba0e613c/codex/epics/SOLM-EPIC-043/INPUT-SOLM-EPIC-043.md)
- decisions/ADR-031-threadmemento-v0.2-breakpointengine-context-thread-memento-peak-guardrail.md (https://github.com/SolLabsHQ/infra-docs/blob/c9e113b487b18b658db19bf145632945ba0e613c/decisions/ADR-031-threadmemento-v0.2-breakpointengine-context-thread-memento-peak-guardrail.md)
- codex/EPIC-042/PR #42: ThreadMemento v0.2 & Markdown Rendering.md (https://github.com/SolLabsHQ/infra-docs/blob/c9e113b487b18b658db19bf145632945ba0e613c/codex/EPIC-042/PR%20%2342%3A%20ThreadMemento%20v0.2%20%26%20Markdown%20Rendering.md)
- codex/EPIC-042/AGENTPACK-EPIC-042.md (https://github.com/SolLabsHQ/infra-docs/blob/c9e113b487b18b658db19bf145632945ba0e613c/codex/EPIC-042/AGENTPACK-EPIC-042.md)
- codex/EPIC-042/INPUT-EPIC-042.md (https://github.com/SolLabsHQ/infra-docs/blob/c9e113b487b18b658db19bf145632945ba0e613c/codex/EPIC-042/INPUT-EPIC-042.md)
<!-- END GENERATED: epic-execution-payload -->
