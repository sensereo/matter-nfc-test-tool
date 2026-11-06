#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:-$app_root/.scratch/dependencies/sdk-connectedhomeip}"
revision="$(cat "$app_root/scripts/matter-revision.txt")"
if [[ -e "$destination" ]]; then
    echo "Destination already exists; supply a new path or use your reviewed checkout." >&2
    exit 1
fi
mkdir -p "$(dirname "$destination")"
git clone --no-checkout https://github.com/nrfconnect/sdk-connectedhomeip.git "$destination"
git -C "$destination" checkout --detach "$revision"
echo "Pinned SDK ready at $destination; build script fetches Darwin submodules."
