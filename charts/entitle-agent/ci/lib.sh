#!/usr/bin/env bash
# =============================================================================
# Shared helpers for entitle-agent CI test scripts.
# =============================================================================
# Provides ANSI colors and the pass/fail/info reporters used by
# credential-validation-test.sh. Source it with:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# Sets FAILED=0; fail() flips it to 1 so callers can exit non-zero.
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

FAILED=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=1; }
info() { echo -e "${YELLOW}>>>${NC} $1"; }
