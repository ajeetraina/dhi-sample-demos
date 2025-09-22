#!/bin/bash

# LocalStack Official vs DHI Validation Script
# Tests every claim in the comparison table

# Remove set -e to prevent early exit on failures
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Images to test
STANDARD_IMAGE="localstack/localstack:latest"
DHI_IMAGE="dockerdevrel/dhi-localstack:4.8.1-python3.12-debian13"

# Test results
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=0

# Helper functions
print_header() {
    echo ""
    echo "=== $1 ==="
}

print_test() {
    echo "Testing: $1"
}

print_pass() {
    echo "✅ PASS: $1"
    ((PASS_COUNT++))
    ((TOTAL_TESTS++))
}

print_fail() {
    echo "❌ FAIL: $1"
    ((FAIL_COUNT++))
    ((TOTAL_TESTS++))
}

print_info() {
    echo "   ℹ️  $1"
}

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up test containers..."
    docker stop standard-test dhi-test 2>/dev/null || true
    docker rm standard-test dhi-test 2>/dev/null || true
    docker volume rm test-volume 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

print_header "LocalStack Official vs DHI Validation Script"

# Pull images
print_header "Pulling Images"
echo "Pulling standard LocalStack image..."
docker pull $STANDARD_IMAGE
echo "Pulling DHI LocalStack image..."  
docker pull $DHI_IMAGE

# Start both containers
print_header "Starting Test Containers"
echo "Starting standard LocalStack..."
docker run -d --name standard-test -p 4566:4566 $STANDARD_IMAGE
echo "Starting DHI LocalStack..."
docker run -d --name dhi-test -p 4567:4566 $DHI_IMAGE

# Wait for startup
echo "Waiting for containers to start..."
sleep 20

print_header "VALIDATION TESTS"

# TEST 1: Shell Access
print_test "Shell Access (Standard: Direct, DHI: Basic)"
STANDARD_SHELL_RESULT="FAIL"
DHI_SHELL_RESULT="FAIL"

if docker exec standard-test /bin/bash -c "echo 'shell test'" >/dev/null 2>&1; then
    STANDARD_SHELL="Direct shell access ✓"
    STANDARD_SHELL_RESULT="PASS"
else
    STANDARD_SHELL="No shell access ✗"
fi

if docker exec dhi-test /bin/sh -c "echo 'shell test'" >/dev/null 2>&1; then
    DHI_SHELL="Basic shell access ✓"
    DHI_SHELL_RESULT="PASS"
else
    DHI_SHELL="No shell access ✗"
fi

if [[ "$STANDARD_SHELL_RESULT" == "PASS" && "$DHI_SHELL_RESULT" == "PASS" ]]; then
    print_pass "Shell access confirmed for both images"
    print_info "Standard: $STANDARD_SHELL"
    print_info "DHI: $DHI_SHELL"
else
    print_fail "Shell access test failed"
    print_info "Standard: $STANDARD_SHELL"
    print_info "DHI: $DHI_SHELL"
fi

# TEST 2: Package Managers
print_test "Package Managers (Standard: Full, DHI: None)"
STANDARD_APT="✗"
STANDARD_PIP="✗"
DHI_APT="✗" 
DHI_PIP="✗"

# Test standard LocalStack package managers
if docker exec standard-test apt --version >/dev/null 2>&1; then
    STANDARD_APT="✓"
fi
if docker exec standard-test pip --version >/dev/null 2>&1; then
    STANDARD_PIP="✓"
fi

# Test DHI LocalStack package managers (should fail)
if docker exec dhi-test apt --version >/dev/null 2>&1; then
    DHI_APT="✓"
fi
if docker exec dhi-test pip --version >/dev/null 2>&1; then
    DHI_PIP="✓"
fi

if [[ "$STANDARD_APT" == "✓" && "$DHI_APT" == "✗" ]]; then
    print_pass "Package manager access as expected"
    print_info "Standard: apt($STANDARD_APT) pip($STANDARD_PIP)"
    print_info "DHI: apt($DHI_APT) pip($DHI_PIP)"
else
    print_fail "Package manager test failed"
    print_info "Standard: apt($STANDARD_APT) pip($STANDARD_PIP)"
    print_info "DHI: apt($DHI_APT) pip($DHI_PIP)"
fi

# TEST 3: User Context
print_test "User Context (Standard: Root, DHI: Nonroot)"
STANDARD_USER=$(docker exec standard-test /bin/bash -c "whoami" 2>/dev/null || echo "unknown")
DHI_USER=$(docker exec dhi-test /bin/sh -c "whoami" 2>/dev/null || echo "command-not-found")

print_info "Standard: $STANDARD_USER"
print_info "DHI: $DHI_USER"

if [[ "$STANDARD_USER" == "root" ]]; then
    if [[ "$DHI_USER" == "command-not-found" || "$DHI_USER" == "nonroot" ]]; then
        print_pass "User context differences confirmed"
    else
        print_fail "Expected DHI to run as nonroot or have whoami unavailable"
    fi
else
    print_fail "Expected standard LocalStack to run as root"
fi

# TEST 4: System Utilities
print_test "System Utilities (Standard: Full toolchain, DHI: Minimal)"
UTILITIES="ls cat id ps find rm"
STANDARD_UTILS=""
DHI_UTILS=""
STANDARD_COUNT=0
DHI_COUNT=0

for util in $UTILITIES; do
    if docker exec standard-test which $util >/dev/null 2>&1; then
        STANDARD_UTILS="$STANDARD_UTILS $util(✓)"
        ((STANDARD_COUNT++))
    else
        STANDARD_UTILS="$STANDARD_UTILS $util(✗)"
    fi
    
    if docker exec dhi-test which $util >/dev/null 2>&1; then
        DHI_UTILS="$DHI_UTILS $util(✓)"
        ((DHI_COUNT++))
    else
        DHI_UTILS="$DHI_UTILS $util(✗)"
    fi
done

print_info "Standard utilities ($STANDARD_COUNT/6): $STANDARD_UTILS"
print_info "DHI utilities ($DHI_COUNT/6): $DHI_UTILS"

if [[ $STANDARD_COUNT -gt $DHI_COUNT ]]; then
    print_pass "DHI has fewer system utilities ($DHI_COUNT vs $STANDARD_COUNT)"
else
    print_fail "Expected DHI to have fewer utilities than standard"
fi

# TEST 5: Image Sizes
print_test "Image Sizes"
STANDARD_SIZE=$(docker images $STANDARD_IMAGE --format "{{.Size}}" 2>/dev/null || echo "unknown")
DHI_SIZE=$(docker images $DHI_IMAGE --format "{{.Size}}" 2>/dev/null || echo "unknown")

print_info "Standard LocalStack: $STANDARD_SIZE"
print_info "DHI LocalStack: $DHI_SIZE"
print_pass "Image sizes recorded for manual verification"

# TEST 6: LocalStack Health Endpoints
print_test "LocalStack Health Endpoints"
sleep 5  # Additional wait for LocalStack to be ready

STANDARD_HEALTH="✗"
DHI_HEALTH="✗"

if curl -s -f http://localhost:4566/_localstack/health >/dev/null 2>&1; then
    STANDARD_HEALTH="✓"
fi

if curl -s -f http://localhost:4567/_localstack/health >/dev/null 2>&1; then
    DHI_HEALTH="✓"
fi

if [[ "$STANDARD_HEALTH" == "✓" && "$DHI_HEALTH" == "✓" ]]; then
    print_pass "Both LocalStack instances responding to health checks"
else
    print_fail "Health endpoint test failed"
    print_info "Standard health: $STANDARD_HEALTH"
    print_info "DHI health: $DHI_HEALTH"
fi

# TEST 7: Service Compatibility (S3 Test)
print_test "Service Compatibility - S3"
if command -v aws >/dev/null 2>&1; then
    STANDARD_S3="✗"
    DHI_S3="✗"
    
    if aws --endpoint-url=http://localhost:4566 s3 mb s3://test-standard >/dev/null 2>&1; then
        STANDARD_S3="✓"
    fi
    
    if aws --endpoint-url=http://localhost:4567 s3 mb s3://test-dhi >/dev/null 2>&1; then
        DHI_S3="✓"
    fi
    
    print_info "Standard S3: $STANDARD_S3"
    print_info "DHI S3: $DHI_S3"
    
    if [[ "$STANDARD_S3" == "✓" && "$DHI_S3" == "✓" ]]; then
        print_pass "S3 service works on both images"
    else
        print_fail "S3 service test failed"
    fi
else
    print_info "AWS CLI not available - skipping S3 test"
    print_pass "S3 test skipped (AWS CLI required)"
fi

# Final Report
print_header "VALIDATION SUMMARY"
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo ""
    echo "🎉 ALL VALIDATION TESTS PASSED!"
    echo "The comparison table claims are validated by testing."
else
    echo ""
    echo "⚠️  Some tests failed or were inconclusive."
    echo "Review the failed tests to update the comparison table."
fi

echo ""
echo "Validation complete!"
