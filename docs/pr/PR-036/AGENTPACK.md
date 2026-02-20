# AGENTPACK — PR-042 — ThreadMemento v0.2 & Markdown Rendering

## Packet files
- INPUT: ./INPUT.md
- CHECKLIST: ./CHECKLIST.md
- FIXLOG: ./FIXLOG.md

## Gates
- unit: xcodebuild test -scheme SolMobile -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj
- lint: xcodebuild test -scheme SolMobile -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj
- integration: xcodebuild test -scheme SolMobile -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj

## Packet Source Docs
- `infra-docs/codex/EPIC-042/AGENTPACK-EPIC-042.md`
- `infra-docs/codex/EPIC-042/PR #42: ThreadMemento v0.2 & Markdown Rendering.md`

## SolMobile EPIC-042 Scope (Backfill)
### Key seams
- `ios/SolMobile/SolMobile/Views/Chat/ThreadDetailView.swift`
- `ios/SolMobile/SolMobile/Actions/TransmissionAction.swift`
- `ios/SolMobile/SolMobile/Connectivity/SolServerClient.swift`
- `ios/SolMobile/SolMobile/Services/SSEService.swift`
- `ios/SolMobile/SolMobile/Services/OutboxService.swift`
- `ios/SolMobile/SolMobile/Models/Message.swift`

### Required behaviors
- Assistant markdown rendering uses Textual in the assistant lane only and only for final assistant responses.
- User messages remain plain text (no markdown rendering lane for user content).
- Markdown image syntax is stripped in v0 before render.
- `/v1/chat` request DTO supports optional `context.thread_memento`.

### Acceptance criteria
- ADR-031 alignment: request `context.thread_memento` support is wired and compatible with server precedence contract.
- ADR-032 alignment: final-only assistant markdown lane remains in effect and remote image markdown is not rendered.
- Packet readers can execute SolMobile EPIC-042 work from this packet without opening external docs.

### Out of scope
- Streaming markdown delta parsing.
- Interactive markdown widgets.
- Remote image rendering in markdown.

<!-- BEGIN GENERATED: canonical-spec-anchor -->
## Canonical Spec Anchor (infra-docs)
- Epic: SOLM-EPIC-042
- Canonical repo: SolLabsHQ/infra-docs
- Canonical commit: dae793fa4a9f601abc4d9fea1fd3a1f5e35504f9
- Canonical epic path: codex/epics/SOLM-EPIC-042/
- Canonical files:
  - decisions/ADR-031-threadmemento-v0.2-breakpointengine-context-thread-memento-peak-guardrail.md (https://github.com/SolLabsHQ/infra-docs/blob/dae793fa4a9f601abc4d9fea1fd3a1f5e35504f9/decisions/ADR-031-threadmemento-v0.2-breakpointengine-context-thread-memento-peak-guardrail.md)
  - decisions/ADR-032-assistant-markdown-textual-final-only-fence-safety-image-stripping.md (https://github.com/SolLabsHQ/infra-docs/blob/dae793fa4a9f601abc4d9fea1fd3a1f5e35504f9/decisions/ADR-032-assistant-markdown-textual-final-only-fence-safety-image-stripping.md)
  - schema/v0/thread_memento.schema.json (https://github.com/SolLabsHQ/infra-docs/blob/dae793fa4a9f601abc4d9fea1fd3a1f5e35504f9/schema/v0/thread_memento.schema.json)
  - schema/v0/api-contracts.md (https://github.com/SolLabsHQ/infra-docs/blob/dae793fa4a9f601abc4d9fea1fd3a1f5e35504f9/schema/v0/api-contracts.md)
  - architecture/solserver/message-processing-gates-v0.md (https://github.com/SolLabsHQ/infra-docs/blob/dae793fa4a9f601abc4d9fea1fd3a1f5e35504f9/architecture/solserver/message-processing-gates-v0.md)
  - architecture/diagrams/solmobile/transmission.md (https://github.com/SolLabsHQ/infra-docs/blob/dae793fa4a9f601abc4d9fea1fd3a1f5e35504f9/architecture/diagrams/solmobile/transmission.md)
Notes:
- If you have a local checkout, set INFRA_DOCS_ROOT to verify locally.
- Otherwise CI will verify via GitHub at the pinned commit.
<!-- END GENERATED: canonical-spec-anchor -->
