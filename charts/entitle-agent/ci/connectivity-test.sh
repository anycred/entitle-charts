#!/usr/bin/env bash
# =============================================================================
# Connectivity test for the entitle-agent Helm chart (QA)
# =============================================================================
# Runs two scenarios on a minikube cluster (Calico CNI) on a GitHub runner:
#
#   A. Baseline       — install the chart with the QA token; verify every agent
#                       pod reaches 1/1 Ready and stays stable (0 restarts).
#                       Proves the agent reaches the QA proxy (agent.qa.entitle.io).
#
#   B. Locked egress  — same install, but a default-deny-egress NetworkPolicy
#                       allows in-cluster traffic (kube-dns, API server) plus
#                       EXTERNAL egress ONLY to the QA proxy IPs on :8080.
#                       We first prove the policy is enforced (a probe pod is
#                       blocked from a non-allowed external host but can reach
#                       the proxy), then verify the agent is still stable-Ready.
#
# The proxy is an AWS ELB that returns a rotating subset of IPs per DNS query,
# so we resolve in a loop, union the results, and add a known-good extra IP.
# If Scenario B ever flakes because the agent's in-cluster DNS returns an ELB IP
# we didn't capture, switch to Cilium + a toFQDNs policy for agent.qa.entitle.io.
#
# Required env var: ENTITLE_AGENT_TOKEN  (base64-encoded QA token blob)
# Requires on PATH: kubectl, helm, dig (dnsutils), python3
# =============================================================================

set -euo pipefail

CHART_DIR="charts/entitle-agent"
VALUES_FILE="${CHART_DIR}/ci/test-token-path.yaml"   # reuse the existing QA test values
NAMESPACE="entitle-conn-test"
RELEASE="entitle-agent"                               # deployment name is fixed to "entitle-agent" by the chart
APP_SELECTOR="app.kubernetes.io/name=entitle-agent"

READY_TIMEOUT=420       # seconds to wait for all pods to become Ready
STABLE_WINDOW=90        # seconds pods must stay Ready with 0 restarts (covers liveness initialDelay+period)
PROXY_PORT=8080         # the agent proxy port: http://agent.<platform>.entitle.io:8080
EXTRA_PROXY_IP="54.170.102.201"   # known-good QA proxy IP supplied by Peleg, always allowed
BLOCKED_TEST_IP="1.1.1.1"         # a public IP that must be BLOCKED under the locked-egress policy

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=1; }
info() { echo -e "${YELLOW}>>>${NC} $1"; }
FAILED=0

# ---------- token / proxy helpers ----------

# Derive the proxy hostname from the token's 'platform' field, mirroring the
# chart's entitle-agent.proxyUrl helper:
#   <platform>      -> agent.<platform>.entitle.io
#   dev-N           -> agent-N.dev.entitle.io
derive_proxy_host() {
  local platform
  platform=$(echo "$ENTITLE_AGENT_TOKEN" | base64 -d 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('platform',''))" 2>/dev/null || echo "")
  if [ -z "$platform" ]; then
    echo "ERROR: could not extract 'platform' from token" >&2
    return 1
  fi
  if [ "${platform#dev-}" != "$platform" ]; then
    echo "agent-${platform#dev-}.dev.entitle.io"
  else
    echo "agent.${platform}.entitle.io"
  fi
}

# Resolve a hostname to a sorted, de-duplicated list of IPv4 addresses. Queries
# several times because the ELB hands back a rotating subset per query.
resolve_ips() {
  local host="$1" _i
  for _i in $(seq 1 8); do
    dig +short "$host" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
  done | sort -u
}

# ---------- pod health helpers ----------

wait_for_ready() {
  info "Waiting up to ${READY_TIMEOUT}s for deployment/${RELEASE} to be Ready..."
  kubectl rollout status "deployment/${RELEASE}" -n "$NAMESPACE" --timeout="${READY_TIMEOUT}s"
}

# Every agent pod must be Ready AND have 0 restarts, sustained over STABLE_WINDOW.
verify_stable() {
  info "Verifying pods stay Ready with 0 restarts for ${STABLE_WINDOW}s..."
  local elapsed=0 step=10 restarts not_ready
  while [ "$elapsed" -lt "$STABLE_WINDOW" ]; do
    restarts=$(kubectl get pods -n "$NAMESPACE" -l "$APP_SELECTOR" \
      -o jsonpath='{range .items[*].status.containerStatuses[*]}{.restartCount}{"\n"}{end}' \
      | awk '{s+=$1} END{print s+0}')
    not_ready=$(kubectl get pods -n "$NAMESPACE" -l "$APP_SELECTOR" \
      -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
      | grep -cv '^True$' || true)
    if [ "${restarts:-0}" -ne 0 ]; then echo "  observed ${restarts} restart(s)"; return 1; fi
    if [ "${not_ready:-1}" -ne 0 ]; then echo "  ${not_ready} pod(s) not Ready"; return 1; fi
    sleep "$step"; elapsed=$((elapsed + step))
  done
  return 0
}

diagnose() {
  info "Diagnostics: $1"
  echo "--- pods ---";          kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || true
  echo "--- describe ---";      kubectl describe pods -n "$NAMESPACE" -l "$APP_SELECTOR" 2>/dev/null | tail -50 || true
  echo "--- events ---";        kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp 2>/dev/null | tail -20 || true
  echo "--- healthcheck init logs ---"
  kubectl logs -n "$NAMESPACE" -l "$APP_SELECTOR" -c "${RELEASE}-healthcheck" --tail=50 2>/dev/null || true
  echo "--- agent logs ---"
  kubectl logs -n "$NAMESPACE" -l "$APP_SELECTOR" -c "$RELEASE" --tail=50 2>/dev/null || true
  echo "--- networkpolicy ---"; kubectl get networkpolicy -n "$NAMESPACE" -o yaml 2>/dev/null || true
}

cleanup() {
  helm uninstall "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 || true
  if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    kubectl delete ns "$NAMESPACE" --wait --timeout=120s >/dev/null 2>&1 || true
  fi
}

install_agent() {
  helm install "$RELEASE" "./$CHART_DIR" \
    -f "$VALUES_FILE" \
    --set "agent.token=${ENTITLE_AGENT_TOKEN}" \
    -n "$NAMESPACE" --wait=false
}

# ---------- egress policy ----------

# Apply a default-deny-egress NetworkPolicy that allows:
#   * all in-cluster / RFC1918 egress (kube-dns, API server, pod-to-pod)
#   * external egress ONLY to the supplied proxy IPs on PROXY_PORT
apply_egress_policy() {
  local ip ip_rules=""
  for ip in "$@"; do
    ip_rules+="        - ipBlock: { cidr: ${ip}/32 }"$'\n'
  done
  # Strip the trailing newline here (in normal shell context); $'\n' is NOT
  # ANSI-C-expanded inside the heredoc below, so the strip must happen first.
  local ip_rules_trimmed="${ip_rules%$'\n'}"
  kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-qa-proxy-only
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # In-cluster / private networks — kube-dns, API server, pod-to-pod. Not "egress from the cluster".
    - to:
        - ipBlock: { cidr: 10.0.0.0/8 }
        - ipBlock: { cidr: 172.16.0.0/12 }
        - ipBlock: { cidr: 192.168.0.0/16 }
    # External egress ONLY to the QA proxy, on the proxy port.
    - to:
${ip_rules_trimmed}
      ports:
        - protocol: TCP
          port: ${PROXY_PORT}
EOF
}

# Run a probe pod (subject to the namespace's NetworkPolicies) that connects to
# URL. Prints "REACHABLE" if it received any HTTP response, else "BLOCKED".
# A 4xx (e.g. the proxy's 403) still counts as REACHABLE — we test connectivity,
# not HTTP status. A dropped/timed-out connection yields http_code 000 -> BLOCKED.
probe_external() {
  local url="$1" name="egress-probe-$RANDOM" out
  out=$(kubectl run "$name" --image=curlimages/curl:8.7.1 --restart=Never -n "$NAMESPACE" \
        --rm -i --command -- sh -c \
        "code=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 '$url' || true); \
         if [ \"\$code\" != '000' ]; then echo REACHABLE; else echo BLOCKED; fi" 2>/dev/null || true)
  if echo "$out" | grep -q REACHABLE; then echo REACHABLE; else echo BLOCKED; fi
}

# ---------- scenarios ----------

run_scenario_a() {
  info "SCENARIO A: baseline — agent reaches the QA proxy (open egress)"
  cleanup
  kubectl create namespace "$NAMESPACE"
  install_agent
  if wait_for_ready && verify_stable; then
    pass "Scenario A: all agent pods 1/1 Ready and stable"
  else
    fail "Scenario A: agent pods did not reach stable Ready"
    diagnose "Scenario A"
  fi
}

run_scenario_b() {
  info "SCENARIO B: locked egress — external egress only to the QA proxy"
  cleanup
  kubectl create namespace "$NAMESPACE"

  local proxy_host ips first_ip
  proxy_host=$(derive_proxy_host) || { fail "Scenario B: could not derive proxy host from token"; return; }
  info "Proxy host (from token platform): ${proxy_host}"

  ips=$( { resolve_ips "$proxy_host"; echo "$EXTRA_PROXY_IP"; } | grep -E '^[0-9]+\.' | sort -u )
  if [ -z "$ips" ]; then
    fail "Scenario B: could not resolve any IP for ${proxy_host}"
    return
  fi
  first_ip=$(echo "$ips" | head -n1)
  info "Allowing external egress on :${PROXY_PORT} to:"
  while IFS= read -r _ip; do echo "    ${_ip}"; done <<< "$ips"

  # shellcheck disable=SC2086
  apply_egress_policy $ips

  # Prove enforcement BEFORE trusting the agent result.
  if [ "$(probe_external "http://${BLOCKED_TEST_IP}")" = "BLOCKED" ]; then
    pass "Scenario B: non-allowed external host (${BLOCKED_TEST_IP}) blocked — policy enforced"
  else
    fail "Scenario B: non-allowed external host reachable — egress NOT enforced (Calico not ready?)"
  fi
  if [ "$(probe_external "http://${first_ip}:${PROXY_PORT}/")" = "REACHABLE" ]; then
    pass "Scenario B: QA proxy ${first_ip}:${PROXY_PORT} reachable through policy"
  else
    fail "Scenario B: QA proxy ${first_ip}:${PROXY_PORT} NOT reachable through policy"
  fi

  install_agent
  if wait_for_ready && verify_stable; then
    pass "Scenario B: all agent pods 1/1 Ready and stable under locked egress"
  else
    fail "Scenario B: agent pods did not reach stable Ready under locked egress"
    diagnose "Scenario B"
  fi
}

# ---------- main ----------

if [ -z "${ENTITLE_AGENT_TOKEN:-}" ]; then
  echo "ERROR: ENTITLE_AGENT_TOKEN env var is required"; exit 1
fi
command -v dig >/dev/null 2>&1 || { echo "ERROR: 'dig' is required (install dnsutils)"; exit 1; }

helm dependency build "$CHART_DIR" >/dev/null 2>&1 || true

run_scenario_a
echo ""
run_scenario_b
echo ""

cleanup
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}All connectivity tests passed!${NC}"; exit 0
else
  echo -e "${RED}Some connectivity tests failed!${NC}"; exit 1
fi
