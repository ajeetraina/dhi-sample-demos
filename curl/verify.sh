#!/bin/bash
# Curl DHI Documentation Verification Script
# This script validates all claims in the "Non-hardened vs Docker Hardened Images" table

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Images to compare
STANDARD_IMAGE="curlimages/curl:latest"
DHI_IMAGE="dockerdevrel/dhi-curl:8.14.1-alpine3.22"

echo "=========================================="
echo "Curl DHI Verification Test Suite"
echo "=========================================="
echo ""
echo "Standard Image: $STANDARD_IMAGE"
echo "DHI Image: $DHI_IMAGE"
echo ""

# Pull images if needed
echo "Pulling images..."
docker pull $STANDARD_IMAGE > /dev/null 2>&1
docker pull $DHI_IMAGE > /dev/null 2>&1

# Test results tracking
PASS=0
FAIL=0
WARN=0

# Helper function to print test results
print_result() {
    local test_name=$1
    local standard_result=$2
    local dhi_result=$3
    local expected_dhi=$4
    
    echo -e "${BLUE}TEST: $test_name${NC}"
    echo "  Standard curl: $standard_result"
    echo "  DHI curl: $dhi_result"
    
    if [[ "$dhi_result" == "$expected_dhi" ]]; then
        echo -e "  ${GREEN}✓ PASS${NC} - DHI behavior matches documentation"
        ((PASS++))
    else
        echo -e "  ${RED}✗ FAIL${NC} - DHI behavior differs from documentation"
        echo "  Expected: $expected_dhi"
        ((FAIL++))
    fi
    echo ""
}

echo "=========================================="
echo "1. SHELL ACCESS TEST"
echo "=========================================="

# Test bash
standard_bash=$(docker run --rm $STANDARD_IMAGE /bin/bash -c "echo 'bash works'" 2>&1 || echo "bash not available")
dhi_bash=$(docker run --rm $DHI_IMAGE /bin/bash -c "echo 'bash works'" 2>&1 || echo "bash not available")

# Test sh
standard_sh=$(docker run --rm $STANDARD_IMAGE /bin/sh -c "echo 'sh works'" 2>&1 || echo "sh not available")
dhi_sh=$(docker run --rm $DHI_IMAGE /bin/sh -c "echo 'sh works'" 2>&1 || echo "sh not available")

echo -e "${BLUE}TEST: Shell Access - bash${NC}"
echo "  Standard curl: $standard_bash"
echo "  DHI curl: $dhi_bash"
if [[ "$dhi_bash" == *"not available"* ]] || [[ "$dhi_bash" == *"not found"* ]]; then
    echo -e "  ${GREEN}✓ DOCUMENTED CORRECTLY${NC} - No bash in DHI"
    ((PASS++))
else
    echo -e "  ${RED}✗ ISSUE${NC} - Bash unexpectedly available"
    ((FAIL++))
fi
echo ""

echo -e "${BLUE}TEST: Shell Access - sh${NC}"
echo "  Standard curl: $standard_sh"
echo "  DHI curl: $dhi_sh"
echo "  Documentation claims: 'Basic shell access (sh)'"
if [[ "$dhi_sh" == *"not available"* ]] || [[ "$dhi_sh" == *"not found"* ]] || [[ "$dhi_sh" == *"no such file"* ]]; then
    echo -e "  ${RED}✗ DOCUMENTATION ERROR${NC} - Documentation claims 'Basic shell access (sh)' but NO shell exists"
    ((FAIL++))
else
    echo -e "  ${GREEN}✓ MATCHES DOCS${NC} - sh available as documented"
    ((PASS++))
fi
echo ""

echo "=========================================="
echo "2. PACKAGE MANAGER TEST"
echo "=========================================="

# Test apk (Alpine package manager)
standard_apk=$(docker run --rm $STANDARD_IMAGE apk --version 2>&1 | head -1 || echo "not available")
dhi_apk=$(docker run --rm $DHI_IMAGE apk --version 2>&1 | head -1 || echo "not available")

echo -e "${BLUE}TEST: Package Manager (apk)${NC}"
echo "  Standard curl: $standard_apk"
echo "  DHI curl: $dhi_apk"
if [[ "$dhi_apk" == *"not available"* ]] || [[ "$dhi_apk" == *"not found"* ]]; then
    echo -e "  ${GREEN}✓ PASS${NC} - apk removed as documented"
    ((PASS++))
else
    echo -e "  ${RED}✗ FAIL${NC} - apk still available"
    ((FAIL++))
fi
echo ""

echo "=========================================="
echo "3. USER IDENTIFICATION TEST"
echo "=========================================="

# Test user with alternative method since whoami/id might be missing
standard_user=$(docker run --rm $STANDARD_IMAGE /bin/sh -c 'echo "UID: $UID"' 2>&1 || echo "cannot check")
dhi_user=$(docker run --rm $DHI_IMAGE /bin/sh -c 'echo "UID: $UID"' 2>&1 || echo "cannot check")

# Test write permissions to root directory
standard_root_write=$(docker run --rm $STANDARD_IMAGE /bin/sh -c 'touch /etc/test-file 2>&1' && echo "can write to /etc" || echo "cannot write to /etc")
dhi_root_write=$(docker run --rm $DHI_IMAGE /bin/sh -c 'touch /etc/test-file 2>&1' && echo "can write to /etc" || echo "cannot write to /etc")

echo -e "${BLUE}TEST: User - Root Write Access${NC}"
echo "  Standard curl: $standard_root_write"
echo "  DHI curl: $dhi_root_write"
if [[ "$dhi_root_write" == *"cannot write"* ]]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Runs as nonroot user (cannot write to /etc)"
    ((PASS++))
else
    echo -e "  ${RED}✗ FAIL${NC} - Can write to /etc (may be running as root)"
    ((FAIL++))
fi
echo ""

echo "=========================================="
echo "4. SYSTEM UTILITIES TEST"
echo "=========================================="

# Test common utilities
utilities=("ls" "cat" "id" "ps" "find" "rm")

for util in "${utilities[@]}"; do
    standard_util=$(docker run --rm $STANDARD_IMAGE /bin/sh -c "$util --version 2>&1 || $util --help 2>&1" | head -1 || echo "not available")
    dhi_util=$(docker run --rm $DHI_IMAGE /bin/sh -c "$util --version 2>&1 || $util --help 2>&1" | head -1 || echo "not available")
    
    echo -e "${BLUE}TEST: System Utility - $util${NC}"
    echo "  Standard curl: $(echo $standard_util | cut -c1-60)..."
    echo "  DHI curl: $(echo $dhi_util | cut -c1-60)..."
    
    if [[ "$dhi_util" == *"not available"* ]] || [[ "$dhi_util" == *"not found"* ]] || [[ "$dhi_util" == *"No such file"* ]]; then
        echo -e "  ${GREEN}✓ PASS${NC} - $util removed as documented"
        ((PASS++))
    else
        echo -e "  ${RED}✗ FAIL${NC} - $util still available"
        ((FAIL++))
    fi
    echo ""
done

echo "=========================================="
echo "5. CURL FUNCTIONALITY TEST"
echo "=========================================="

# Test basic curl operation
standard_curl=$(docker run --rm $STANDARD_IMAGE --version | head -1)
dhi_curl=$(docker run --rm $DHI_IMAGE --version | head -1)

echo -e "${BLUE}TEST: Curl Version${NC}"
echo "  Standard curl: $standard_curl"
echo "  DHI curl: $dhi_curl"
if [[ "$dhi_curl" == curl* ]]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Curl binary works"
    ((PASS++))
else
    echo -e "  ${RED}✗ FAIL${NC} - Curl not working"
    ((FAIL++))
fi
echo ""

# Test HTTPS/SSL
echo -e "${BLUE}TEST: HTTPS/SSL Support${NC}"
dhi_https=$(docker run --rm $DHI_IMAGE -I https://www.docker.com 2>&1 | grep -i "HTTP" | head -1 || echo "failed")
echo "  DHI curl HTTPS test: $dhi_https"
if [[ "$dhi_https" == *"HTTP"* ]]; then
    echo -e "  ${GREEN}✓ PASS${NC} - HTTPS/SSL works"
    ((PASS++))
else
    echo -e "  ${RED}✗ FAIL${NC} - HTTPS/SSL failed"
    ((FAIL++))
fi
echo ""

echo "=========================================="
echo "6. IMAGE SIZE TEST"
echo "=========================================="

standard_size=$(docker images $STANDARD_IMAGE --format "{{.Size}}")
dhi_size=$(docker images $DHI_IMAGE --format "{{.Size}}")

echo -e "${BLUE}TEST: Image Size${NC}"
echo "  Standard curl: $standard_size"
echo "  DHI curl: $dhi_size"
echo "  Documentation claims: ~18MB (uncompressed)"
echo -e "  ${YELLOW}ℹ INFO${NC} - Size comparison (smaller is better for DHI)"
((WARN++))
echo ""

echo "=========================================="
echo "7. ENTRYPOINT TEST"
echo "=========================================="

standard_entrypoint=$(docker inspect $STANDARD_IMAGE --format='{{.Config.Entrypoint}}')
dhi_entrypoint=$(docker inspect $DHI_IMAGE --format='{{.Config.Entrypoint}}')

echo -e "${BLUE}TEST: Entrypoint Configuration${NC}"
echo "  Standard curl: $standard_entrypoint"
echo "  DHI curl: $dhi_entrypoint"
if [[ "$dhi_entrypoint" == *"curl"* ]]; then
    echo -e "  ${GREEN}✓ PASS${NC} - Entrypoint set to curl"
    ((PASS++))
else
    echo -e "  ${YELLOW}⚠ WARN${NC} - Unexpected entrypoint"
    ((WARN++))
fi
echo ""

echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo -e "${GREEN}PASSED: $PASS${NC}"
echo -e "${RED}FAILED: $FAIL${NC}"
echo -e "${YELLOW}WARNINGS: $WARN${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}⚠ DOCUMENTATION ISSUES FOUND${NC}"
    echo "Review failed tests above and update documentation accordingly."
    exit 1
else
    echo -e "${GREEN}✓ ALL CRITICAL TESTS PASSED${NC}"
    exit 0
fi
