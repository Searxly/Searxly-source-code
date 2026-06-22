#!/usr/bin/env bash
# Runs the security-boundary known-answer tests (approval previews + prompt-injection guard).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/SecurityBoundaryTests"
cd "$DIR"
swift run -Xswiftc -suppress-warnings
