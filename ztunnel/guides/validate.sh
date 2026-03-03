#!/bin/bash
# ============================================================================
# DHI Ztunnel Guide Validation Script
# Tests every code snippet in guides.md against a live environment
# ============================================================================
#
# Prerequisites:
#   - Docker Desktop with Kubernetes enabled
#   - helm CLI installed
#   - kubectl CLI configured
#   - DHI registry credentials
#
# Usage:
#   export DHI_USERNAME="your-username"
#   export DHI_PASSWORD="your-token"
#   export DHI_EMAIL="your-email"
#   bash validate-guide.sh
#
# ============================================================================

set -euo pipefail

# --- Configuration ---
DHI_USERNAME="${DHI_USERNAME:?Set DHI_USERNAME}"
DHI_PASSWORD="${DHI_PASSWORD:?Set DHI_PASSWORD}"
DHI_EMAIL="${DHI_EMAIL:?Set DHI_EMAIL}"

BASE_CHART_VERSION="1.0.0"
DISCOVERY_CHART_VERSION="1.28.4"
CNI_CHART_VERSION="1.28.4"
CNI_IMAGE_TAG="1.28"
ZTUNNEL_CHART_VERSION="1.27.7"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

# --- Helpers ---
log()  { echo -e "\n\033[1;34m[$1]\033[0m $2"; }
pass() { echo -e "  \033[1;32m✅ PASS:\033[0m $1"; PASS=$((PASS+1)); RESULTS+=("PASS: $1"); }
fail() { echo -e "  \033[1;31m❌ FAIL:\033[0m $1"; FAIL=$((FAIL+1)); RESULTS+=("FAIL: $1"); }
skip() { echo -e "  \033[1;33m⏭  SKIP:\033[0m $1"; SKIP=$((SKIP+1)); RESULTS+=("SKIP: $1"); }

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# --- Cleanup from previous runs ---
log "CLEANUP" "Removing previous installations if any"
helm uninstall ztunnel -n istio-system --no-hooks 2>/dev/null || true
helm uninstall istio-cni -n istio-system --no-hooks 2>/dev/null || true
helm uninstall istiod -n istio-system --no-hooks 2>/dev/null || true
helm uninstall istio-base -n istio-system --no-hooks 2>/dev/null || true
kubectl delete namespace istio-system --wait=false 2>/dev/null || true
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/bookinfo/platform/kube/bookinfo.yaml 2>/dev/null || true
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/sleep/sleep.yaml 2>/dev/null || true
kubectl label namespace default istio.io/dataplane-mode- 2>/dev/null || true
sleep 10
# Ensure namespace is fully gone before recreating
kubectl wait --for=delete namespace/istio-system --timeout=60s 2>/dev/null || true

# ============================================================================
# SECTION: Prerequisite — docker login dhi.io (line 11)
# ============================================================================
log "PREREQ" "docker login dhi.io"
echo "$DHI_PASSWORD" | docker login dhi.io -u "$DHI_USERNAME" --password-stdin 2>/dev/null \
    && pass "docker login dhi.io" || fail "docker login dhi.io"

# ============================================================================
# SECTION: Start a ztunnel instance (lines 23-90)
# ============================================================================

# Line 35: helm registry login dhi.io
log "START" "helm registry login dhi.io"
echo "$DHI_PASSWORD" | helm registry login dhi.io -u "$DHI_USERNAME" --password-stdin 2>/dev/null \
    && pass "helm registry login dhi.io" || fail "helm registry login dhi.io"

# Lines 41-47: kubectl create namespace + secret
log "START" "kubectl create namespace istio-system"
check "kubectl create namespace istio-system" \
    kubectl create namespace istio-system

log "START" "kubectl create secret docker-registry dhi-pull-secret -n istio-system"
kubectl create secret docker-registry dhi-pull-secret \
    --docker-server=dhi.io \
    --docker-username="$DHI_USERNAME" \
    --docker-password="$DHI_PASSWORD" \
    --docker-email="$DHI_EMAIL" \
    -n istio-system \
    && pass "kubectl create secret dhi-pull-secret -n istio-system" \
    || fail "kubectl create secret dhi-pull-secret -n istio-system"

# Lines 53-54: helm install istio-base
log "START" "helm install istio-base oci://dhi.io/istio-base-chart"
helm install istio-base oci://dhi.io/istio-base-chart --version "$BASE_CHART_VERSION" \
    -n istio-system --wait 2>&1 \
    && pass "helm install istio-base" || fail "helm install istio-base"

# Lines 55-58: helm install istiod
log "START" "helm install istiod oci://dhi.io/istio-discovery-chart"
helm install istiod oci://dhi.io/istio-discovery-chart --version "$DISCOVERY_CHART_VERSION" \
    -n istio-system \
    --set "global.imagePullSecrets[0]=dhi-pull-secret" \
    --set profile=ambient --wait 2>&1 \
    && pass "helm install istiod" || fail "helm install istiod"

# Lines 64-71: helm install istio-cni (upstream + DHI image)
log "START" "helm repo add istio"
check "helm repo add istio" \
    helm repo add istio https://istio-release.storage.googleapis.com/charts

log "START" "helm install istio-cni istio/cni with DHI image override"
helm install istio-cni istio/cni --version "$CNI_CHART_VERSION" \
    -n istio-system \
    --set hub=dhi.io \
    --set image=istio-install-cni \
    --set tag="$CNI_IMAGE_TAG" \
    --set "global.imagePullSecrets[0]=dhi-pull-secret" \
    --set ambient.enabled=true --wait 2>&1 \
    && pass "helm install istio-cni" || fail "helm install istio-cni"

# Lines 80-83: helm install ztunnel
log "START" "helm install ztunnel oci://dhi.io/ztunnel-chart"
helm install ztunnel oci://dhi.io/ztunnel-chart --version "$ZTUNNEL_CHART_VERSION" \
    --namespace istio-system \
    --set "imagePullSecrets[0]=dhi-pull-secret" \
    --wait 2>&1 \
    && pass "helm install ztunnel" || fail "helm install ztunnel"

# Line 89: kubectl get pods -n istio-system -l app=ztunnel
log "START" "Verify ztunnel pods running"
ZTUNNEL_READY=$(kubectl get pods -n istio-system -l app=ztunnel --no-headers 2>/dev/null | grep -c "Running" || true)
if [ "$ZTUNNEL_READY" -ge 1 ]; then
    pass "kubectl get pods -n istio-system -l app=ztunnel ($ZTUNNEL_READY running)"
else
    fail "kubectl get pods -n istio-system -l app=ztunnel (0 running)"
fi

# ============================================================================
# SECTION: Ambient mesh use case (lines 94-126)
# ============================================================================

# Line 104: kubectl label namespace
log "USE CASE" "kubectl label namespace default istio.io/dataplane-mode=ambient"
check "kubectl label namespace default ambient" \
    kubectl label namespace default istio.io/dataplane-mode=ambient

# Lines 110-111: Deploy sample workloads
log "USE CASE" "Deploy bookinfo + sleep"
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/bookinfo/platform/kube/bookinfo.yaml 2>&1 \
    && pass "kubectl apply bookinfo" || fail "kubectl apply bookinfo"

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/sleep/sleep.yaml 2>&1 \
    && pass "kubectl apply sleep" || fail "kubectl apply sleep"

# Wait for pods
log "USE CASE" "Waiting for workload pods to be ready (up to 120s)"
kubectl wait --for=condition=ready pod -l app=productpage --timeout=120s 2>/dev/null \
    && pass "productpage pod ready" || fail "productpage pod not ready"
kubectl wait --for=condition=ready pod -l app=sleep --timeout=120s 2>/dev/null \
    && pass "sleep pod ready" || fail "sleep pod not ready"

# Line 117: curl test
log "USE CASE" "kubectl exec deploy/sleep -- curl productpage:9080"
HTTP_CODE=$(kubectl exec deploy/sleep -- curl -s -o /dev/null -w "%{http_code}" http://productpage:9080/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "curl productpage returns 200"
else
    fail "curl productpage returns $HTTP_CODE (expected 200)"
fi

# Line 125: ztunnel logs for mTLS
log "USE CASE" "kubectl logs ztunnel — verify SPIFFE identities"
LOGS=$(kubectl logs -n istio-system -l app=ztunnel --tail=50 2>/dev/null)
if echo "$LOGS" | grep -q "spiffe://"; then
    pass "ztunnel logs contain SPIFFE identities (mTLS active)"
else
    fail "ztunnel logs missing SPIFFE identities"
fi

# ============================================================================
# SECTION: FIPS use case (lines 128-157) — SKIP (requires Enterprise)
# ============================================================================
log "FIPS" "FIPS deployment and verification"
skip "helm install ztunnel --set tag=<tag>-fips (requires DHI Enterprise subscription)"
skip "kubectl get pod ... jsonpath env grep fips (requires FIPS deployment)"

# ============================================================================
# SECTION: Deploy in Kubernetes (lines 159-183)
# ============================================================================

# Line 167: kubectl get pods -o wide
log "K8S DEPLOY" "kubectl get pods -n istio-system -l app=ztunnel -o wide"
WIDE_OUTPUT=$(kubectl get pods -n istio-system -l app=ztunnel -o wide 2>/dev/null)
if echo "$WIDE_OUTPUT" | grep -q "Running"; then
    pass "kubectl get pods -o wide shows Running ztunnel pods"
else
    fail "kubectl get pods -o wide — no Running pods"
fi

# Line 173: enroll namespace (already enrolled, re-label to test idempotency)
log "K8S DEPLOY" "kubectl label namespace default ambient (idempotent)"
kubectl label namespace default istio.io/dataplane-mode=ambient --overwrite 2>/dev/null \
    && pass "kubectl label namespace ambient (overwrite)" || fail "kubectl label namespace ambient (overwrite)"

# Line 179: remove namespace from mesh
log "K8S DEPLOY" "kubectl label namespace default istio.io/dataplane-mode-"
kubectl label namespace default istio.io/dataplane-mode- 2>/dev/null \
    && pass "kubectl label namespace remove ambient" || fail "kubectl label namespace remove ambient"

# Verify traffic still works without mesh
log "K8S DEPLOY" "Traffic works after removing from mesh"
sleep 3
HTTP_CODE=$(kubectl exec deploy/sleep -- curl -s -o /dev/null -w "%{http_code}" http://productpage:9080/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "curl productpage returns 200 (no mesh)"
else
    fail "curl productpage returns $HTTP_CODE after mesh removal"
fi

# Re-enroll
log "K8S DEPLOY" "Re-enroll namespace in ambient mesh"
check "kubectl label namespace ambient (re-enroll)" \
    kubectl label namespace default istio.io/dataplane-mode=ambient

# ============================================================================
# SECTION: DOI vs DHI table validation (lines 185-198)
# ============================================================================
log "DOI vs DHI" "Validating comparison table claims via docker inspect"

# Pull images
docker pull dhi.io/ztunnel:1.28 >/dev/null 2>&1 || true
docker pull dhi.io/ztunnel:1.28-dev >/dev/null 2>&1 || true
docker pull istio/ztunnel:1.28.4 >/dev/null 2>&1 || true

# DHI User = nonroot
DHI_USER=$(docker inspect --format '{{.Config.User}}' dhi.io/ztunnel:1.28 2>/dev/null)
if [ "$DHI_USER" = "nonroot" ]; then
    pass "DHI User = nonroot"
else
    fail "DHI User = '$DHI_USER' (expected nonroot)"
fi

# DOI User = empty
DOI_USER=$(docker inspect --format '{{.Config.User}}' istio/ztunnel:1.28.4 2>/dev/null)
if [ -z "$DOI_USER" ]; then
    pass "DOI User = empty (defaults to root)"
else
    fail "DOI User = '$DOI_USER' (expected empty)"
fi

# DHI Entrypoint = ["ztunnel"]
DHI_EP=$(docker inspect --format '{{json .Config.Entrypoint}}' dhi.io/ztunnel:1.28 2>/dev/null)
if [ "$DHI_EP" = '["ztunnel"]' ]; then
    pass "DHI Entrypoint = [\"ztunnel\"]"
else
    fail "DHI Entrypoint = '$DHI_EP' (expected [\"ztunnel\"])"
fi

# DOI Entrypoint = ["/usr/local/bin/ztunnel"]
DOI_EP=$(docker inspect --format '{{json .Config.Entrypoint}}' istio/ztunnel:1.28.4 2>/dev/null)
if [ "$DOI_EP" = '["/usr/local/bin/ztunnel"]' ]; then
    pass "DOI Entrypoint = [\"/usr/local/bin/ztunnel\"]"
else
    fail "DOI Entrypoint = '$DOI_EP'"
fi

# DHI Shell = No (runtime)
docker run --rm --entrypoint sh dhi.io/ztunnel:1.28 -c "echo hello" >/dev/null 2>&1 \
    && fail "DHI runtime has shell (expected no shell)" \
    || pass "DHI runtime has no shell"

# DOI Shell = Yes
docker run --rm --entrypoint sh istio/ztunnel:1.28.4 -c "echo hello" >/dev/null 2>&1 \
    && pass "DOI has shell" \
    || fail "DOI has no shell (expected shell)"

# Dev variant: shell + root + pkg manager
DHI_DEV_USER=$(docker inspect --format '{{.Config.User}}' dhi.io/ztunnel:1.28-dev 2>/dev/null)
if [ "$DHI_DEV_USER" = "root" ]; then
    pass "DHI dev User = root"
else
    fail "DHI dev User = '$DHI_DEV_USER' (expected root)"
fi

docker run --rm --entrypoint sh dhi.io/ztunnel:1.28-dev -c "echo hello" >/dev/null 2>&1 \
    && pass "DHI dev has shell" \
    || fail "DHI dev has no shell (expected shell)"

docker run --rm --entrypoint sh dhi.io/ztunnel:1.28-dev -c "apt --version" >/dev/null 2>&1 \
    && pass "DHI dev has package manager (apt)" \
    || fail "DHI dev has no package manager"

# DHI compliance labels
DHI_COMPLIANCE=$(docker inspect --format '{{index .Config.Labels "com.docker.dhi.compliance"}}' dhi.io/ztunnel:1.28 2>/dev/null)
if [ "$DHI_COMPLIANCE" = "cis" ]; then
    pass "DHI compliance label = cis"
else
    fail "DHI compliance label = '$DHI_COMPLIANCE' (expected cis)"
fi

# DHI distro = debian-13
DHI_DISTRO=$(docker inspect --format '{{index .Config.Labels "com.docker.dhi.distro"}}' dhi.io/ztunnel:1.28 2>/dev/null)
if [ "$DHI_DISTRO" = "debian-13" ]; then
    pass "DHI distro label = debian-13"
else
    fail "DHI distro label = '$DHI_DISTRO' (expected debian-13)"
fi

# ============================================================================
# SECTION: Image variants (lines 200-227)
# ============================================================================
log "VARIANTS" "Runtime variant claims"
DHI_SHELL_LABEL=$(docker inspect --format '{{index .Config.Labels "com.docker.dhi.shell"}}' dhi.io/ztunnel:1.28 2>/dev/null)
if [ -z "$DHI_SHELL_LABEL" ]; then
    pass "Runtime shell label = empty (no shell)"
else
    fail "Runtime shell label = '$DHI_SHELL_LABEL'"
fi

DHI_PKG_LABEL=$(docker inspect --format '{{index .Config.Labels "com.docker.dhi.package-manager"}}' dhi.io/ztunnel:1.28 2>/dev/null)
if [ -z "$DHI_PKG_LABEL" ]; then
    pass "Runtime package-manager label = empty (no pkg mgr)"
else
    fail "Runtime package-manager label = '$DHI_PKG_LABEL'"
fi

log "VARIANTS" "FIPS variant pull (expects 401 without Enterprise)"
docker pull dhi.io/ztunnel:1.28-fips >/dev/null 2>&1 \
    && skip "FIPS pull succeeded (has Enterprise access)" \
    || pass "FIPS pull failed with 401 (confirms Enterprise required)"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "============================================================================"
echo "  VALIDATION SUMMARY"
echo "============================================================================"
echo ""
for r in "${RESULTS[@]}"; do
    case "$r" in
        PASS*) echo -e "  \033[32m$r\033[0m" ;;
        FAIL*) echo -e "  \033[31m$r\033[0m" ;;
        SKIP*) echo -e "  \033[33m$r\033[0m" ;;
    esac
done
echo ""
echo "============================================================================"
echo -e "  \033[32mPASS: $PASS\033[0m  |  \033[31mFAIL: $FAIL\033[0m  |  \033[33mSKIP: $SKIP\033[0m  |  TOTAL: $((PASS+FAIL+SKIP))"
echo "============================================================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
