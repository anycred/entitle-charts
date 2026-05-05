#!/usr/bin/env bash
# =============================================================================
# Integration tests for entitle-agent Helm chart
# =============================================================================
# Runs 3 scenarios against a real cluster (kind/minikube):
#   1. Token path — agent.token set directly
#   2. SecretRef only — hook extracts imageCredentials + datadogApiKey
#   3. SecretRef + own registry — hook extracts datadogApiKey only
#
# Required env var: ENTITLE_AGENT_TOKEN (base64-encoded token blob)
# =============================================================================

set -euo pipefail

CHART_DIR="charts/entitle-agent"
CI_DIR="${CHART_DIR}/ci"
NAMESPACE="entitle-ci"
RELEASE="entitle-agent"
TIMEOUT=120  # seconds to wait for pods

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=1; }
info() { echo -e "${YELLOW}>>>${NC} $1"; }

FAILED=0

# ---------- Helpers ----------

cleanup() {
  helm uninstall "$RELEASE" -n "$NAMESPACE" 2>/dev/null || true
  kubectl delete namespace "$NAMESPACE" --wait --timeout=60s 2>/dev/null || true
}

wait_for_pod() {
  local label="$1"
  local expected_ready="$2"
  local elapsed=0

  while [ $elapsed -lt $TIMEOUT ]; do
    local status
    status=$(kubectl get pods -n "$NAMESPACE" -l "$label" -o jsonpath='{.items[0].status.containerStatuses[*].ready}' 2>/dev/null || echo "")

    # Count true values
    local ready_count
    ready_count=$(echo "$status" | tr ' ' '\n' | grep -c "true" 2>/dev/null || echo "0")
    ready_count=$(echo "$ready_count" | tr -d '[:space:]')

    if [ "${ready_count:-0}" -eq "$expected_ready" ] 2>/dev/null; then
      return 0
    fi

    # Check for CrashLoopBackOff
    local phase
    phase=$(kubectl get pods -n "$NAMESPACE" -l "$label" -o jsonpath='{.items[0].status.containerStatuses[?(@.ready==false)].state.waiting.reason}' 2>/dev/null || echo "")
    if echo "$phase" | grep -q "CrashLoopBackOff"; then
      echo "  Pod is in CrashLoopBackOff"
      kubectl logs -n "$NAMESPACE" -l "$label" --tail=10 2>/dev/null || true
      return 1
    fi

    sleep 3
    elapsed=$((elapsed + 3))
  done

  echo "  Timed out after ${TIMEOUT}s"
  kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
  return 1
}

check_secret_exists() {
  local name="$1"
  if kubectl get secret "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

check_deployment_image_pull_secret() {
  local expected="$1"
  local actual
  actual=$(kubectl get deployment "$RELEASE" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.imagePullSecrets[0].name}' 2>/dev/null || echo "")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  echo "  Expected imagePullSecret: $expected, got: $actual"
  return 1
}

# ---------- Pre-flight ----------

if [ -z "${ENTITLE_AGENT_TOKEN:-}" ]; then
  echo "ERROR: ENTITLE_AGENT_TOKEN env var is required"
  exit 1
fi

helm dependency build "$CHART_DIR" >/dev/null 2>&1

# ==========================================================================
# TEST 1: Token path
# ==========================================================================
info "TEST 1: Token path (agent.token set directly)"
cleanup
kubectl create namespace "$NAMESPACE"

helm install "$RELEASE" "./$CHART_DIR" \
  -f "${CI_DIR}/test-token-path.yaml" \
  --set "agent.token=${ENTITLE_AGENT_TOKEN}" \
  -n "$NAMESPACE" --wait=false

# Verify secrets
if check_secret_exists "entitle-agent-secret"; then
  pass "Test 1: agent secret created"
else
  fail "Test 1: agent secret NOT created"
fi

if check_secret_exists "entitle-agent-docker-login"; then
  pass "Test 1: docker-login secret created (auto-extracted from token)"
else
  fail "Test 1: docker-login secret NOT created"
fi

# Verify pod comes up
if wait_for_pod "app.kubernetes.io/name=entitle-agent" 1; then
  pass "Test 1: agent pod 1/1 Ready"
else
  fail "Test 1: agent pod NOT ready"
fi

# Verify imagePullSecrets references the chart-managed secret
if check_deployment_image_pull_secret "entitle-agent-docker-login"; then
  pass "Test 1: imagePullSecrets correct"
else
  fail "Test 1: imagePullSecrets incorrect"
fi

echo ""

# ==========================================================================
# TEST 2: SecretRef only (hook extracts everything)
# ==========================================================================
info "TEST 2: SecretRef only (hook extracts imageCredentials + datadogApiKey)"
cleanup
kubectl create namespace "$NAMESPACE"

# Create the pre-existing token secret
kubectl create secret generic entitle-agent-ci-token \
  --from-literal=ENTITLE_JSON_CONFIGURATION="{\"BASE64_CONFIGURATION\":\"${ENTITLE_AGENT_TOKEN}\"}" \
  -n "$NAMESPACE"

helm install "$RELEASE" "./$CHART_DIR" \
  -f "${CI_DIR}/test-secretref-only.yaml" \
  -n "$NAMESPACE" --wait=false

# Verify hook-created secrets
sleep 10  # give hook time to run
if check_secret_exists "entitle-agent-docker-login"; then
  pass "Test 2: docker-login secret created by hook"
else
  fail "Test 2: docker-login secret NOT created by hook"
fi

# Verify the chart did NOT create entitle-agent-secret (no token in values)
if ! check_secret_exists "entitle-agent-secret"; then
  pass "Test 2: no chart-managed agent secret (expected with secretRef)"
else
  fail "Test 2: chart-managed agent secret exists unexpectedly"
fi

# Verify pod comes up
if wait_for_pod "app.kubernetes.io/name=entitle-agent" 1; then
  pass "Test 2: agent pod 1/1 Ready"
else
  fail "Test 2: agent pod NOT ready"
fi

# Verify imagePullSecrets references the hook-created secret
if check_deployment_image_pull_secret "entitle-agent-docker-login"; then
  pass "Test 2: imagePullSecrets correct (hook-created)"
else
  fail "Test 2: imagePullSecrets incorrect"
fi

echo ""

# ==========================================================================
# TEST 3: SecretRef + own registry (hook extracts datadogApiKey only)
# ==========================================================================
info "TEST 3: SecretRef + own registry (user provides imagePullSecret)"
cleanup
kubectl create namespace "$NAMESPACE"

# Create the pre-existing token secret
kubectl create secret generic entitle-agent-ci-token \
  --from-literal=ENTITLE_JSON_CONFIGURATION="{\"BASE64_CONFIGURATION\":\"${ENTITLE_AGENT_TOKEN}\"}" \
  -n "$NAMESPACE"

# Create the pre-existing registry secret (extract imageCredentials from token)
IMAGE_CREDS=$(echo "${ENTITLE_AGENT_TOKEN}" | base64 -d | python3 -c "import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)['imageCredentials']).decode())")
kubectl create secret docker-registry entitle-agent-ci-registry \
  --from-file=.dockerconfigjson=<(echo "$IMAGE_CREDS") \
  -n "$NAMESPACE"

helm install "$RELEASE" "./$CHART_DIR" \
  -f "${CI_DIR}/test-secretref-registry.yaml" \
  -n "$NAMESPACE" --wait=false

# Verify the hook did NOT create docker-login (user provides own)
sleep 10
if ! check_secret_exists "entitle-agent-docker-login"; then
  pass "Test 3: no hook-created docker-login (user provides own registry secret)"
else
  fail "Test 3: hook-created docker-login exists unexpectedly"
fi

# Verify pod comes up
if wait_for_pod "app.kubernetes.io/name=entitle-agent" 1; then
  pass "Test 3: agent pod 1/1 Ready"
else
  fail "Test 3: agent pod NOT ready"
fi

# Verify imagePullSecrets references the user-provided secret
if check_deployment_image_pull_secret "entitle-agent-ci-registry"; then
  pass "Test 3: imagePullSecrets correct (user-provided)"
else
  fail "Test 3: imagePullSecrets incorrect"
fi

echo ""

# ---------- Summary ----------
cleanup
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}All integration tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some integration tests failed!${NC}"
  exit 1
fi
