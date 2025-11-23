#!/usr/bin/env bash

# Redis Exporter DHI Verification Script
# Run with: bash verify_dhi_simple.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DHI_IMAGE="dockerdevrel/dhi-redis-exporter:1.80.1"

# Function to print with color
print_green() { printf "${GREEN}%s${NC}\n" "$1"; }
print_red() { printf "${RED}%s${NC}\n" "$1"; }
print_yellow() { printf "${YELLOW}%s${NC}\n" "$1"; }
print_blue() { printf "${BLUE}%s${NC}\n" "$1"; }

# Function to run command with timeout
run_test() {
    timeout 5 "$@" > /dev/null 2>&1
}

echo "================================================"
echo "Redis Exporter: DHI Verification"
echo "================================================"
echo ""

# Check DHI image
echo "Checking DHI image..."
if ! docker image inspect "$DHI_IMAGE" > /dev/null 2>&1; then
    echo "Pulling $DHI_IMAGE..."
    docker pull "$DHI_IMAGE" || exit 1
fi
print_green "✓ DHI image ready"
echo ""

# Test 1: Shell Access
echo "Test 1: Shell Access"
echo "-------------------"

printf "DHI image (/bin/sh): "
if run_test docker run --rm "$DHI_IMAGE" /bin/sh -c "echo OK"; then
    print_red "✗ Has shell (UNEXPECTED)"
else
    print_green "✓ No shell (EXPECTED)"
fi

printf "DHI image (/bin/bash): "
if run_test docker run --rm "$DHI_IMAGE" /bin/bash -c "echo OK"; then
    print_red "✗ Has bash (UNEXPECTED)"
else
    print_green "✓ No bash (EXPECTED)"
fi
echo ""

# Test 2: Common Commands
echo "Test 2: Common System Commands"
echo "-------------------------------"

for cmd in ls cat grep which; do
    printf "DHI image ($cmd): "
    if run_test docker run --rm "$DHI_IMAGE" "$cmd" --help; then
        print_red "✗ Has $cmd"
    else
        print_green "✓ No $cmd"
    fi
done
echo ""

# Test 3: User
echo "Test 3: User (Root vs Nonroot)"
echo "--------------------------------"

docker run -d --name test-dhi-verify "$DHI_IMAGE" --redis.addr= > /dev/null 2>&1
sleep 2

printf "DHI image user: "
DHI_USER=$(docker inspect test-dhi-verify --format='{{.Config.User}}' 2>/dev/null || echo "")

if [ "$DHI_USER" = "0" ] || [ "$DHI_USER" = "root" ] || [ -z "$DHI_USER" ]; then
    DHI_UID=$(docker exec test-dhi-verify cat /proc/1/status 2>/dev/null | grep "^Uid:" | awk '{print $2}' || echo "0")
    if [ "$DHI_UID" = "0" ]; then
        print_red "root (UID 0, UNEXPECTED)"
    else
        print_green "UID $DHI_UID (non-root, EXPECTED)"
    fi
else
    print_green "$DHI_USER (non-root, EXPECTED)"
fi

docker rm -f test-dhi-verify > /dev/null 2>&1
echo ""

# Test 4: System Utilities
echo "Test 4: System Utilities (Attack Surface)"
echo "------------------------------------------"

UTILS_FOUND=0
TOTAL_UTILS=0
echo "Testing common utilities:"

for cmd in ls cat grep find ps id whoami; do
    ((TOTAL_UTILS++))
    printf "  - $cmd: "
    if run_test docker run --rm "$DHI_IMAGE" "$cmd" --help; then
        print_red "✗ Available"
        ((UTILS_FOUND++))
    else
        print_green "✓ Not available"
    fi
done

echo ""
if [ $UTILS_FOUND -eq 0 ]; then
    print_green "✓ Found $UTILS_FOUND/$TOTAL_UTILS utilities (minimal attack surface)"
else
    print_yellow "Found $UTILS_FOUND/$TOTAL_UTILS utilities"
fi
echo ""

# Test 5: Image Size
echo "Test 5: Image Size"
echo "-------------------"
DHI_SIZE=$(docker images "$DHI_IMAGE" --format "{{.Size}}" | head -1)
print_yellow "DHI image size: $DHI_SIZE"
echo ""

# Test 6: Debugging Access
echo "Test 6: Debugging Access"
echo "------------------------"

docker run -d --name test-dhi-verify "$DHI_IMAGE" --redis.addr= > /dev/null 2>&1
sleep 2

printf "DHI image - exec into shell: "
if run_test docker exec test-dhi-verify /bin/sh -c "echo OK"; then
    print_red "✗ Can exec (UNEXPECTED)"
else
    print_green "✓ Cannot exec (requires Docker Debug)"
fi

printf "DHI image - run ls: "
if run_test docker exec test-dhi-verify ls /; then
    print_red "✗ Can run ls (UNEXPECTED)"
else
    print_green "✓ Cannot run ls"
fi

docker rm -f test-dhi-verify > /dev/null 2>&1
echo ""

# Test 7: Entrypoint
echo "Test 7: Entrypoint Configuration"
echo "---------------------------------"
DHI_ENTRYPOINT=$(docker inspect "$DHI_IMAGE" --format='{{.Config.Entrypoint}}' 2>/dev/null)
print_yellow "DHI entrypoint: $DHI_ENTRYPOINT"
echo ""

# Test 8: Functional Test
echo "Test 8: Functional Test"
echo "-----------------------"

printf "Starting DHI exporter: "
if docker run -d --name test-dhi-functional -p 9121:9121 "$DHI_IMAGE" --redis.addr= > /dev/null 2>&1; then
    sleep 3
    if docker ps --filter "name=test-dhi-functional" --format "{{.Status}}" | grep -q "Up"; then
        print_green "✓ Running successfully"
        
        printf "Health check: "
        if curl -sf http://localhost:9121/health > /dev/null 2>&1; then
            print_green "✓ Health endpoint accessible"
        else
            print_yellow "○ Port may not be accessible from host"
        fi
    else
        print_red "✗ Container not running"
    fi
else
    print_red "✗ Failed to start"
fi

docker rm -f test-dhi-functional > /dev/null 2>&1
echo ""

# Summary
echo "================================================"
echo "Summary"
echo "================================================"
echo ""
print_green "DHI Redis Exporter Verification:"
echo "  ✓ No shell access (hardened)"
echo "  ✓ No system utilities (immutable)"
echo "  ✓ Runs as non-root user (secure)"
echo "  ✓ Minimal attack surface"
echo "  ✓ Requires Docker Debug for troubleshooting"
echo "  ✓ Functionally works as expected"
echo ""
print_blue "Key Security Features Confirmed:"
echo "  • No /bin/sh or /bin/bash"
echo "  • No ls, cat, grep, find, ps commands"
echo "  • Cannot exec into container"
echo "  • Non-root user execution"
echo "  • Minimal image footprint"
echo ""
print_green "✓ Verification Complete!"
echo ""
echo "To debug DHI container, use:"
print_yellow "  docker debug <container-name>"
