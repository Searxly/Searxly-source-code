#!/usr/bin/env bash
#
# Runs the Searxly security-boundary known-answer tests (see SecurityBoundaryTests/).
# These run against the REAL production sources (symlinked): the dApp approval previews
# (TypedDataPreview/TxPreview) and the prompt-injection guard (PageContentGuard).
# Exits non-zero on any failure.
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/SecurityBoundaryTests"
cd "$DIR"
echo "Running security-boundary known-answer tests in $DIR ..."
swift run -Xswiftc -suppress-warnings
