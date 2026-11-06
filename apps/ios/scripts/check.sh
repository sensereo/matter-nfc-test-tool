#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_root"
mkdir -p .scratch
swift test --scratch-path .scratch/swift-build
clang++ -std=c++17 -Wall -Wextra -Werror TestsNative/NFCDiscoveryGateTests.cpp -o .scratch/nfc-discovery-gate-tests
.scratch/nfc-discovery-gate-tests
ruby -c scripts/generate-project.rb
ruby -c scripts/prepare-matter-project.rb
for script in scripts/*.sh; do
    bash -n "$script"
done
plutil -lint App/Info.plist App/MatterNFCTest.entitlements
