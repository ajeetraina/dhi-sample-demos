#!/bin/bash

# DHI Validation Script for dockerdevrel/dhi-grist:1.7.3-debian13
# Usage: ./validate-dhi.sh <container-id-or-name>

CONTAINER_ID=$1
IMAGE="dockerdevrel/dhi-grist:1.7.3-debian13"

if [ -z "$CONTAINER_ID" ]; then
    echo "Usage: $0 <container-id-or-name>"
    exit 1
fi

echo "=========================================="
echo "DHI Validation Report"
echo "=========================================="
echo "Image: $IMAGE"
echo "Container: $CONTAINER_ID"
echo "Date: $(date)"
echo ""

PASSED=0
FAILED=0
WARNING=0

# ==========================================
# 1. Nonroot User Check
# ==========================================
echo "1. NONROOT USER"
echo "-------------------------------------------"

CURRENT_UID=$(docker exec $CONTAINER_ID id -u)
CURRENT_GID=$(docker exec $CONTAINER_ID id -g)
CURRENT_USER=$(docker exec $CONTAINER_ID whoami)

echo "   Current UID: $CURRENT_UID"
echo "   Current GID: $CURRENT_GID"
echo "   Current User: $CURRENT_USER"

if [ "$CURRENT_UID" != "0" ]; then
    echo "[PASS] Running as nonroot user (UID: $CURRENT_UID)"
    PASSED=$((PASSED+1))
else
    echo "[FAIL] Running as root (UID: 0)"
    FAILED=$((FAILED+1))
fi
echo ""

# ==========================================
# 2. Shell Availability
# ==========================================
echo "2. SHELL AVAILABILITY"
echo "-------------------------------------------"

SHELL_FOUND=0
for shell in /bin/sh /bin/bash /bin/dash /bin/ash; do
    if docker exec $CONTAINER_ID test -f $shell 2>/dev/null; then
        echo "   Found: $shell"
        SHELL_FOUND=1
    fi
done

if [ $SHELL_FOUND -eq 1 ]; then
    echo "[FAIL] Shell exists (DHI runtime should not have shell)"
    FAILED=$((FAILED+1))
else
    echo "[PASS] No shell found (as expected for DHI runtime)"
    PASSED=$((PASSED+1))
fi
echo ""

# ==========================================
# 3. Package Manager Check
# ==========================================
echo "3. PACKAGE MANAGERS"
echo "-------------------------------------------"

PKG_FOUND=0
for pm in apt-get apt apk yum dnf; do
    if docker exec $CONTAINER_ID which $pm 2>/dev/null >/dev/null; then
        PM_PATH=$(docker exec $CONTAINER_ID which $pm 2>/dev/null)
        echo "   Found: $pm at $PM_PATH"
        PKG_FOUND=1
    fi
done

if [ $PKG_FOUND -eq 1 ]; then
    echo "[FAIL] Package manager exists (DHI runtime should not have package managers)"
    FAILED=$((FAILED+1))
else
    echo "[PASS] No package managers found (as expected for DHI runtime)"
    PASSED=$((PASSED+1))
fi
echo ""

# ==========================================
# 4. TLS Certificates
# ==========================================
echo "4. TLS CERTIFICATES"
echo "-------------------------------------------"

CERTS_FOUND=0
for cert_path in /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs /etc/pki/tls/certs; do
    if docker exec $CONTAINER_ID test -e $cert_path 2>/dev/null; then
        echo "   Found: $cert_path"
        CERTS_FOUND=1
    fi
done

if [ $CERTS_FOUND -eq 1 ]; then
    echo "[PASS] TLS certificates are present"
    PASSED=$((PASSED+1))
else
    echo "[FAIL] No TLS certificates found"
    FAILED=$((FAILED+1))
fi
echo ""

# ==========================================
# 5. Port Configuration
# ==========================================
echo "5. PORT CONFIGURATION"
echo "-------------------------------------------"

# Check for port 8484
docker exec $CONTAINER_ID netstat -tlnp 2>/dev/null | grep :8484 && echo "[PASS] Grist listening on non-privileged port 8484" && PASSED=$((PASSED+1)) || echo "[INFO] Could not verify port (netstat may not be available)"

echo ""

# ==========================================
# 6. Entry Point and CMD
# ==========================================
echo "6. ENTRY POINT AND CMD"
echo "-------------------------------------------"

ENTRYPOINT=$(docker inspect --format='{{.Config.Entrypoint}}' $CONTAINER_ID)
CMD=$(docker inspect --format='{{.Config.Cmd}}' $CONTAINER_ID)

echo "   Entrypoint: $ENTRYPOINT"
echo "   Cmd: $CMD"
echo ""

# ==========================================
# 7. File System Permissions
# ==========================================
echo "7. FILE SYSTEM PERMISSIONS"
echo "-------------------------------------------"

for dir in /persist /grist /tmp; do
    if docker exec $CONTAINER_ID test -d $dir 2>/dev/null; then
        WRITABLE=$(docker exec $CONTAINER_ID test -w $dir && echo "YES" || echo "NO")
        echo "   $dir: Writable by nonroot user: $WRITABLE"
        
        if [ "$WRITABLE" == "YES" ]; then
            PASSED=$((PASSED+1))
        else
            WARNING=$((WARNING+1))
        fi
    fi
done
echo ""

# ==========================================
# 8. Development Tools Check
# ==========================================
echo "8. DEVELOPMENT TOOLS CHECK"
echo "-------------------------------------------"

DEV_FOUND=0
for tool in gcc make git curl wget vim nano; do
    if docker exec $CONTAINER_ID which $tool 2>/dev/null >/dev/null; then
        echo "   Found: $tool"
        DEV_FOUND=1
    fi
done

if [ $DEV_FOUND -eq 0 ]; then
    echo "[PASS] No development tools found (minimal image)"
    PASSED=$((PASSED+1))
else
    echo "[WARN] Development tools present (image may not be minimal)"
    WARNING=$((WARNING+1))
fi
echo ""

# ==========================================
# 9. Image Information
# ==========================================
echo "9. IMAGE INFORMATION"
echo "-------------------------------------------"

IMAGE_SIZE=$(docker images $IMAGE --format "{{.Size}}" 2>/dev/null || echo "Unknown")
echo "   Image size: $IMAGE_SIZE"

docker exec $CONTAINER_ID cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" || echo "   OS: Unknown"
echo ""

# ==========================================
# Summary
# ==========================================
echo "=========================================="
echo "VALIDATION SUMMARY"
echo "=========================================="
echo "Passed:   $PASSED"
echo "Failed:   $FAILED"
echo "Warnings: $WARNING"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "Overall: Image validation completed"
elif [ $FAILED -le 2 ]; then
    echo "Overall: Image has some deviations from standard DHI runtime pattern"
else
    echo "Overall: Image does not match standard DHI runtime pattern"
fi
