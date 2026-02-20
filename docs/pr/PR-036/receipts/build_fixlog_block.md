### 2026-02-19 22:55 — Builder gates run

- unit: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj`
- lint: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj`
- integration: `xcodebuild test -scheme SolMobileTests -destination 'platform=iOS Simulator,name=iPhone 17' -project ios/SolMobile/SolMobile.xcodeproj`

Results:
- unit rc: 0
- lint rc: 0
- integration rc: 0

Receipts:
- `receipts/unit.log`
- `receipts/lint.log`
- `receipts/integration.log`
