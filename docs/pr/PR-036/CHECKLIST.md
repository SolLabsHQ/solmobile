# CHECKLIST — PR-036

- [x] unit (AUTO) — Evidence: Command: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj` | Result: PASS | Log: `docs/pr/PR-036/receipts/unit.log`
- [x] lint (AUTO) — Evidence: Command: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj` | Result: PASS | Log: `docs/pr/PR-036/receipts/lint.log`
- [x] integration (AUTO) — Evidence: Command: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj` | Result: PASS | Log: `docs/pr/PR-036/receipts/integration.log`
- [x] spec-lock verify (AUTO) — Evidence: Command: `unset INFRA_DOCS_ROOT; PR_NUM=36 ./scripts/verify_spec_lock.sh --pr-num 36` | Result: PASS | Log: `stdout`
