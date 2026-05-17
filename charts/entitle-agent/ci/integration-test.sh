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
POD_READY_TIMEOUT=300  # seconds to wait for pod Ready (1/1)

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
  if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl delete namespace "$NAMESPACE" --wait --timeout=60s
  fi
}

wait_for_pod_running() {
  # Waits for a pod to be in Running state (container started, image pulled).
  local label="$1"
  local elapsed=0

  while [ $elapsed -lt $TIMEOUT ]; do
    local phase
    phase=$(kubectl get pods -n "$NAMESPACE" -l "$label" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")

    if [ "$phase" = "Running" ]; then
      return 0
    fi

    # Check for permanent failures
    local waiting_reason
    waiting_reason=$(kubectl get pods -n "$NAMESPACE" -l "$label" -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
    if echo "$waiting_reason" | grep -qE "ImagePullBackOff|ErrImagePull|InvalidImageName"; then
      echo "  Pod failed: $waiting_reason"
      kubectl describe pod -n "$NAMESPACE" -l "$label" 2>/dev/null | tail -5 || true
      return 1
    fi

    sleep 3
    elapsed=$((elapsed + 3))
  done

  echo "  Timed out after ${TIMEOUT}s"
  kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
  return 1
}

wait_for_pod_ready() {
  # Waits for a pod to be 1/1 Ready (startup probe passed).
  local label="$1"
  local elapsed=0

  while [ $elapsed -lt $POD_READY_TIMEOUT ]; do
    local ready
    ready=$(kubectl get pods -n "$NAMESPACE" -l "$label" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

    if [ "$ready" = "true" ]; then
      return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done

  return 1
}

diagnose_pod() {
  # Collect diagnostic info for a pod that isn't becoming Ready
  local label="$1"
  local test_name="$2"

  info "Diagnostics for ${test_name}"

  echo "--- Pod status ---"
  kubectl get pods -n "$NAMESPACE" -l "$label" -o wide 2>/dev/null || true

  echo "--- Pod events ---"
  kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp 2>/dev/null | grep -i entitle | tail -10 || true

  echo "--- Agent logs (last 30 lines) ---"
  kubectl logs -n "$NAMESPACE" -l "$label" --tail=30 2>/dev/null || true

  echo "--- Network connectivity from inside the cluster ---"
  # Test DNS + TCP to Kafka and agent.entitle.io from a debug pod
  kubectl run net-diag --image=busybox --restart=Never -n "$NAMESPACE" --rm -i --timeout=30s --command -- sh -c '
    echo "=== DNS resolution ==="
    nslookup agent.entitle.io 2>&1 || echo "DNS FAILED for agent.entitle.io"
    nslookup b-1-public.entitleqakafka.9pmm5z.c4.kafka.eu-west-1.amazonaws.com 2>&1 || echo "DNS FAILED for Kafka"

    echo "=== TCP connectivity ==="
    echo "Testing agent.entitle.io:443..."
    timeout 5 sh -c "cat < /dev/null > /dev/tcp/agent.entitle.io/443" 2>/dev/null && echo "OK" || wget -T 5 -q --spider https://agent.entitle.io 2>&1 && echo "HTTPS OK" || echo "FAILED"

    echo "Testing Kafka broker:9196..."
    timeout 5 sh -c "cat < /dev/null > /dev/tcp/b-1-public.entitleqakafka.9pmm5z.c4.kafka.eu-west-1.amazonaws.com/9196" 2>/dev/null && echo "OK" || echo "FAILED (trying wget)..."
    wget -T 5 -q -O /dev/null "http://b-1-public.entitleqakafka.9pmm5z.c4.kafka.eu-west-1.amazonaws.com:9196" 2>&1 || echo "(wget expected to fail on non-HTTP, but connection was attempted)"
  ' 2>&1 || echo "(net-diag pod finished)"

  echo "--- End diagnostics ---"
  echo ""
}

check_secret_exists() {
  local name="$1"
  kubectl get secret "$name" -n "$NAMESPACE" >/dev/null 2>&1
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

# Verify pod reaches Running state (image pulled, container started)
if wait_for_pod_running "app.kubernetes.io/name=entitle-agent"; then
  pass "Test 1: agent pod Running"
else
  fail "Test 1: agent pod NOT running"
fi

# Verify imagePullSecrets references the chart-managed secret
if check_deployment_image_pull_secret "entitle-agent-docker-login"; then
  pass "Test 1: imagePullSecrets correct"
else
  fail "Test 1: imagePullSecrets incorrect"
fi

# Check if pod becomes Ready (1/1) — informational only.
# The startup probe requires AWS S3 connectivity (no IAM in CI), so Ready
# is not expected in kind clusters. Running is sufficient for chart validation.
if wait_for_pod_ready "app.kubernetes.io/name=entitle-agent"; then
  pass "Test 1: agent pod 1/1 Ready"
else
  info "Test 1: agent pod not Ready (expected — startup probe requires AWS connectivity)"
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
if wait_for_pod_running "app.kubernetes.io/name=entitle-agent"; then
  pass "Test 2: agent pod Running"
else
  fail "Test 2: agent pod NOT running"
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
if wait_for_pod_running "app.kubernetes.io/name=entitle-agent"; then
  pass "Test 3: agent pod Running"
else
  fail "Test 3: agent pod NOT running"
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
