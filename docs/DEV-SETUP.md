# Dev Setup

Requirements:
- Xcode (latest stable)

Notes:
- ADRs live in `infra-docs`. Add decisions there and link back here.

First run:
1) Create/open the Xcode project under `/ios`
2) Build + run on a simulator

## Parallel installs (Dev + Prod)
In Xcode, set `PRODUCT_BUNDLE_IDENTIFIER` per configuration:
- Debug: `com.sollabshq.solmobile.dev`
- Release: `com.sollabshq.solmobile`

Optionally set `INFOPLIST_KEY_CFBundleDisplayName` per configuration:
- Debug: `SolMobile Dev`
- Release: `SolMobile`

## Repo hygiene notes
- The Xcode project under `/ios` must be tracked as normal files (not a nested git repo / submodule).
- Do not commit `.DS_Store` (clean with `find . -name .DS_Store -delete`).


## Bundle IDs (parallel Dev/Prod)
We support side-by-side installs for dogfooding:
- Prod (App Store / TestFlight): `com.sollabshq.solmobile`
- Dev (local Debug build): `com.sollabshq.solmobile.dev`

Recommended display names:
- Prod: `SolMobile`
- Dev: `SolMobile Dev`
