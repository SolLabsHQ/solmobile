# INPUT — PR-042 — ThreadMemento v0.2 & Markdown Rendering

Coordinate this packet with `AGENTPACK.md` and keep receipts in `docs/pr/PR-036/receipts/`.

## Packet Source Docs
- `infra-docs/codex/EPIC-042/AGENTPACK-EPIC-042.md`
- `infra-docs/codex/EPIC-042/PR #42: ThreadMemento v0.2 & Markdown Rendering.md`

## SolMobile Packet Execution Payload (PR-036)
### Key seams to verify
- `ios/SolMobile/SolMobile/Views/Chat/ThreadDetailView.swift`
- `ios/SolMobile/SolMobile/Actions/TransmissionAction.swift`
- `ios/SolMobile/SolMobile/Connectivity/SolServerClient.swift`
- `ios/SolMobile/SolMobile/Services/SSEService.swift`
- `ios/SolMobile/SolMobile/Services/OutboxService.swift`
- `ios/SolMobile/SolMobile/Models/Message.swift`

### Required implementation behavior
- Assistant markdown rendering is Textual-based, assistant-only, and final-only.
- User messages stay plain text.
- Markdown image syntax is stripped in v0 before render.
- Client request DTO includes optional `context.thread_memento` and passes it through to `/v1/chat`.

### Acceptance expectations (ADR-031/ADR-032)
- ThreadMemento request context behavior is present and compatible with server precedence.
- Assistant markdown rendering remains final-only and assistant-only.
- No remote image markdown rendering path is enabled.

### Out of scope for this packet
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
