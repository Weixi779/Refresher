#!/bin/bash
set -euo pipefail
refresher_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$refresher_root"
mode="${1:-all}"
case "$mode" in unit|ui|all) ;; *) echo "Usage: Scripts/test.sh [unit|ui|all] [SIMULATOR_UDID]" >&2; exit 2 ;; esac
simulator_id="${2:-}"
if [[ -z "$simulator_id" ]]; then
    simulator_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; print(next((d["udid"] for group in devices.values() for d in group if d["state"] == "Booted"), ""))')"
fi
if [[ -z "$simulator_id" ]]; then
    echo "Boot an iOS simulator in Xcode, or pass its UDID as the second argument." >&2
    exit 2
fi
mkdir -p "$refresher_root/Artifacts"
run_dir="$(mktemp -d "$refresher_root/Artifacts/test-XXXXXX")"
run_test() {
    local suite="$1"
    shift
    echo "Running $suite tests; results: $run_dir/$suite.xcresult"
    if ! xcodebuild test "$@" -destination "platform=iOS Simulator,id=$simulator_id" \
        -derivedDataPath "$refresher_root/Artifacts/DerivedData-$suite" \
        -resultBundlePath "$run_dir/$suite.xcresult" > "$run_dir/$suite.log" 2>&1; then
        tail -80 "$run_dir/$suite.log"
        return 1
    fi
    tail -12 "$run_dir/$suite.log"
}
if [[ "$mode" == unit || "$mode" == all ]]; then run_test unit -scheme Refresher; fi
if [[ "$mode" == ui || "$mode" == all ]]; then
    run_test ui -project Example/RefresherExample.xcodeproj -scheme RefresherExample -parallel-testing-enabled NO
fi
