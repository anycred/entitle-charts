#!/usr/bin/env bash
# =============================================================================
# Render-time tests for the entitle-agent credential validator (ICH-4992)
# =============================================================================
# Cluster-free: uses `helm template` to assert that the chart fails install
# with a clear message when imageCredentials / datadogApiKey cannot be resolved,
# and renders successfully on every path where they can (or aren't needed).
#
# No real credentials required — tokens here are dummy base64 JSON blobs.
# Run from the repo root:  bash charts/entitle-agent/ci/render-test.sh
# =============================================================================

set -uo pipefail

CHART_DIR="charts/entitle-agent"
RELEASE="rendertest"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=1; }
info() { echo -e "${YELLOW}>>>${NC} $1"; }

FAILED=0

# Dummy token blobs (base64-encoded JSON).
TOKEN_NO_CREDS=$(printf '%s' '{"test":"x"}' | base64)
TOKEN_IMG_ONLY=$(printf '%s' '{"imageCredentials":"e30="}' | base64)
TOKEN_BOTH=$(printf '%s' '{"imageCredentials":"e30=","datadogApiKey":"dd-key-123"}' | base64)

render() {
  # Renders the chart with the given --set args; captures combined output.
  helm template "$RELEASE" "$CHART_DIR" "$@" 2>&1
}

expect_fail() {
  # expect_fail "<description>" "<message substring>" <helm --set args...>
  local desc="$1" needle="$2"; shift 2
  local out
  out=$(render "$@")
  if [ $? -eq 0 ]; then
    fail "$desc — render succeeded but a failure was expected"
  elif echo "$out" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc — failed without expected message '$needle'"
    echo "$out" | grep -i error | head -3
  fi
}

expect_success() {
  # expect_success "<description>" <helm --set args...>
  local desc="$1"; shift
  local out
  out=$(render "$@")
  if [ $? -eq 0 ]; then
    pass "$desc"
  else
    fail "$desc — render failed unexpectedly"
    echo "$out" | grep -i error | head -3
  fi
}

# Datadog subchart must be available for `helm template` to resolve.
helm dependency build "$CHART_DIR" >/dev/null 2>&1 || true

info "Render-time credential validation tests"

# Missing imageCredentials (old token), datadog off, no pull secret -> fail.
expect_fail "imageCredentials missing -> clear failure" "imageCredentials is missing" \
  --set agent.token="$TOKEN_NO_CREDS" --set datadog.enabled=false

# Missing datadogApiKey while datadog enabled (imageCredentials present) -> fail.
expect_fail "datadogApiKey missing (datadog enabled) -> clear failure" "datadogApiKey is missing" \
  --set agent.token="$TOKEN_IMG_ONLY" --set datadog.enabled=true

# Token carries both fields, datadog enabled -> success.
expect_success "token with both fields renders" \
  --set agent.token="$TOKEN_BOTH" --set datadog.enabled=true

# imageCredentials absent from token but user supplies their own registry secret -> success.
expect_success "imagePullSecret.name override renders" \
  --set agent.token="$TOKEN_NO_CREDS" --set datadog.enabled=false --set imagePullSecret.name=my-registry

# datadogApiKey absent from token but datadog disabled -> success.
expect_success "datadog disabled renders without datadogApiKey" \
  --set agent.token="$TOKEN_IMG_ONLY" --set datadog.enabled=false

# secretRef path (no token at render time): validation is skipped, Job validates at runtime.
expect_success "secretRef runtime path skips render-time validation" \
  --set agent.secretRef.name=entitle-agent-token --set datadog.enabled=false

echo ""
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}All render-time tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some render-time tests failed!${NC}"
  exit 1
fi
