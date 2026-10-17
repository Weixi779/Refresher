#!/bin/bash
set -euo pipefail
refresher_root="$(cd "$(dirname "$0")/.." && pwd)"
pager_root="${1:?Usage: test-pager-integration.sh /path/to/Pager SIMULATOR_UDID}"
simulator_id="${2:?Pass a booted iOS Simulator UDID}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/RefresherPager.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/Sources" "$test_root/Tests"
cp -R "$refresher_root/Sources/Refresher" "$test_root/Sources/"
cp -R "$pager_root/Sources/Pager" "$test_root/Sources/"
cp -R "$refresher_root/Tests/RefresherTests" "$test_root/Tests/"
cat > "$test_root/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RefresherPagerIntegration",
    platforms: [.iOS(.v16)],
    products: [.library(name: "Refresher", targets: ["Refresher"])],
    targets: [
        .target(name: "Refresher", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "Pager", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "RefresherTests", dependencies: ["Refresher", "Pager"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
SWIFT
cd "$test_root"
xcodebuild test -scheme RefresherPagerIntegration -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$test_root/DerivedData" -parallel-testing-enabled NO \
    -only-testing:RefresherTests/StickyPagerRefreshTests CODE_SIGNING_ALLOWED=NO
