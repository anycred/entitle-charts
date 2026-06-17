#!/usr/bin/env bash
# =============================================================================
# Credential-validator tests for the entitle-agent Helm chart (ICH-4992)
# =============================================================================
# Cluster-free: uses `helm template` to assert that the chart fails install
# with a clear message when imageCredentials / datadogApiKey cannot be resolved
# (from the agent.token or an explicit --set value), and renders successfully
# on every path where they can (or aren't needed).
#
# No real credentials required — tokens here are dummy base64 JSON blobs.
# Run from the repo root:  bash charts/entitle-agent/ci/credential-validation-test.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

CHART_DIR="charts/entitle-agent"
RELEASE="credvalidation"

# Dummy token blobs (base64-encoded JSON).
TOKEN_NO_CREDS=$(printf '%s' '{"test":"x"}' | base64)
TOKEN_IMG_ONLY=$(printf '%s' '{"imageCredentials":"e30="}' | base64)
TOKEN_BOTH=$(printf '%s' '{"imageCredentials":"e30=","datadogApiKey":"dd-key-123"}' | base64)

assert_render() {
  # assert_render "<description>" <expect_success: true|false> "<message substring>" <helm --set args...>
  # On expect_success=false the message substring must appear in the render error.
  local desc="$1" expect_success="$2" needle="$3"; shift 3
  local out; out=$(helm template "$RELEASE" "$CHART_DIR" "$@" 2>&1)
  local exit_code=$?

  if [ "$expect_success" = "true" ] && [ $exit_code -eq 0 ]; then
    pass "$desc"
  elif [ "$expect_success" = "false" ] && [ $exit_code -ne 0 ] && echo "$out" | grep -qF "$needle"; then
    pass "$desc (fails correctly)"
  else
    fail "$desc"
    echo "$out" | grep -i error | head -n 2
  fi
}

# Datadog subchart must be available for `helm template` to resolve.
helm dependency build "$CHART_DIR" >/dev/null 2>&1 || true

info "Render-time credential validation tests"

# Missing imageCredentials (old token), datadog off, no pull secret -> fail.
assert_render "imageCredentials missing" false "imageCredentials is missing" \
  --set agent.token="$TOKEN_NO_CREDS" --set datadog.enabled=false

# Missing datadogApiKey while datadog enabled (imageCredentials present) -> fail.
assert_render "datadogApiKey missing (datadog enabled)" false "datadogApiKey is missing" \
  --set agent.token="$TOKEN_IMG_ONLY" --set datadog.enabled=true

# Token carries both fields, datadog enabled -> success.
assert_render "token with both fields renders" true "" \
  --set agent.token="$TOKEN_BOTH" --set datadog.enabled=true

# imageCredentials absent from token but user supplies their own registry secret -> success.
assert_render "imagePullSecret.name override renders" true "" \
  --set agent.token="$TOKEN_NO_CREDS" --set datadog.enabled=false --set imagePullSecret.name=my-registry

# datadogApiKey absent from token but datadog disabled -> success.
assert_render "datadog disabled renders without datadogApiKey" true "" \
  --set agent.token="$TOKEN_IMG_ONLY" --set datadog.enabled=false

# secretRef path (no token at render time): validation is skipped, Job validates at runtime.
assert_render "secretRef runtime path skips render-time validation" true "" \
  --set agent.secretRef.name=entitle-agent-token --set datadog.enabled=false

echo ""
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}All credential-validation tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some credential-validation tests failed!${NC}"
  exit 1
fi
