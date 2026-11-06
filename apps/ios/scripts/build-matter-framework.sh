#!/bin/bash
# Build the pinned Nordic Darwin framework without changing the App's signing.
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
matter_source="${1:-$app_root/.scratch/dependencies/sdk-connectedhomeip}"
matter_source="$(cd "$matter_source" && pwd)"
expected_revision="$(cat "$app_root/scripts/matter-revision.txt")"
configuration="${2:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo "Expected Debug or Release" >&2; exit 1 ;; esac
actual_revision="$(git -C "$matter_source" rev-parse HEAD)"
if [[ "$actual_revision" != "$expected_revision" ]]; then
    echo "Wrong Matter revision: expected $expected_revision, got $actual_revision" >&2
    exit 1
fi
if ! git -C "$matter_source" diff --quiet HEAD -- . ':(exclude)build_overrides/pigweed_environment.gni'; then
    echo "Matter checkout has tracked changes; record and review patches before building." >&2
    exit 1
fi
mkdir -p "$app_root/.scratch"
cd "$matter_source"
python3 scripts/checkout_submodules.py --shallow --platform darwin

# Pigweed may regenerate build_overrides/pigweed_environment.gni during setup.
# Use its downloaded build tools without resolving the entire optional Python tool suite.
matter_env="$matter_source/.environment"
if [[ -x "$matter_env/cipd/packages/pigweed/gn" && -x "$matter_env/gn_out/python-venv/bin/python" ]]; then
    export PATH="$matter_env/cipd/packages/pigweed:$matter_env/cipd/packages/pigweed/bin:$matter_env/gn_out/python-venv/bin:$PATH"
    export _PW_ACTUAL_ENVIRONMENT_ROOT="$matter_env"
else
    # Supply HTTPS_PROXY / SSL_CERT_FILE externally when required; never disable TLS validation.
    set +u
    source scripts/activate.sh
    set -eu
fi
for tool in gn ninja python3; do
    if ! command -v "$tool" >/dev/null; then
        echo "Matter environment incomplete: missing $tool. Inspect bootstrap errors." >&2
        exit 1
    fi
done
BUNDLE_GEMFILE="$app_root/Gemfile" bundle exec ruby "$app_root/scripts/prepare-matter-project.rb" "$matter_source"
CHIP_NO_SUBMODULES=1 CHIP_NO_ACTIVATE=1 xcodebuild \
    -project "$app_root/.scratch/MatterBridgeProject/Matter.xcodeproj" \
    -scheme 'NFC Matter Framework' -configuration "$configuration" \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$app_root/.scratch/MatterFramework" \
    CODE_SIGNING_ALLOWED=NO build
