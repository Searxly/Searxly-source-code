#!/usr/bin/env bash
#
# Runs the Searxly wallet crypto known-answer tests (see WalletCryptoTests/README.md).
# These run against the REAL wallet sources (symlinked), catching broken hashes/derivation
# that the live empty-wallet test cannot. Exits non-zero on any failure.
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/WalletCryptoTests"
cd "$DIR"
echo "Running wallet crypto known-answer tests in $DIR ..."
swift run -Xswiftc -suppress-warnings
