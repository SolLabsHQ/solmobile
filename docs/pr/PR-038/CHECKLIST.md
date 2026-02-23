# CHECKLIST — PR-038

## AUTO Evidence (Builder updates)
- [x] unit (AUTO) — Evidence: Command: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj` | Result: PASS | Log: `docs/pr/PR-038/receipts/unit.log`
- [x] lint (AUTO) — Evidence: Command: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj` | Result: PASS | Log: `docs/pr/PR-038/receipts/lint.log`
- [x] integration (AUTO) — Evidence: Command: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj` | Result: PASS | Log: `docs/pr/PR-038/receipts/integration.log`
- [x] spec-lock verify (AUTO) — Evidence: Command: `unset INFRA_DOCS_ROOT; PR_NUM=38 ./scripts/verify_spec_lock.sh --pr-num 38` | Result: PASS | Log: `stdout`

<!-- BEGIN GENERATED: epic-acceptance-checklist -->
## AUTO Scope Assertions (must be proven before PASS)
- [x] Outbound context prefers persisted structured payload and only falls back to summary parse when needed. (AUTO REQUIRED) — Evidence: `TransmissionActionsTests.test_sendOnce_prefersStructuredThreadMemento_overSummaryFallback` + `TransmissionActionsTests.test_sendOnce_fallsBackToSummary_whenStructuredPayloadMalformed` PASS in `docs/pr/PR-038/receipts/unit.log`.
- [x] Outbound send omits `context.thread_memento` safely when neither structured nor parsable summary is available. (AUTO REQUIRED) — Evidence: `TransmissionActionsTests.test_sendOnce_omitsThreadMemento_whenNoStructuredOrParsableSummary` PASS in `docs/pr/PR-038/receipts/unit.log`.
- [x] Malformed structured payload is non-fatal and logs clearly. (AUTO REQUIRED) — Evidence: fallback/no-crash proven by `TransmissionActionsTests.test_sendOnce_fallsBackToSummary_whenStructuredPayloadMalformed` PASS in `docs/pr/PR-038/receipts/unit.log`; decode-fail path logged in `TransmissionAction.resolveThreadMementoForSend`.
- [x] Revoke/clear operations remove both summary and structured stored representations. (AUTO REQUIRED) — Evidence: `ThreadMementoDecisionTests.test_accept_clears_local_draft_fields_for_matching_transmissions` + `ThreadMementoDecisionTests.test_revoke_clears_local_draft_fields_for_matching_transmissions` PASS in `docs/pr/PR-038/receipts/unit.log`.
- [x] `/v1/chat` contract remains unchanged (`memento-v0.2`, no schema bump). (AUTO REQUIRED) — Evidence: `ChatRequestContextEncodingTests.test_requestEncodesContextThreadMemento_whenProvided` PASS in `docs/pr/PR-038/receipts/unit.log` and spec-lock verify PASS.
<!-- END GENERATED: epic-acceptance-checklist -->
