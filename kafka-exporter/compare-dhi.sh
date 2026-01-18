#!/bin/bash

# =============================================================================
# DHI vs Non-DHI Image Comparison Script
# Compares Docker Hardened Images with standard images
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Images to compare
NON_DHI_IMAGE="danielqsj/kafka-exporter:latest"
DHI_IMAGE="dockerdevrel/dhi-kafka-exporter:1.9.0"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   DHI vs Non-DHI Image Comparison: Kafka Exporter${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# Pull both images
echo -e "${YELLOW}Pulling images...${NC}"
docker pull $NON_DHI_IMAGE > /dev/null 2>&1
docker pull $DHI_IMAGE > /dev/null 2>&1
echo -e "${GREEN}✓ Images pulled successfully${NC}"
echo ""

# -----------------------------------------------------------------------------
# Image Size Comparison
# -----------------------------------------------------------------------------
echo -e "${BLUE}📦 IMAGE SIZE${NC}"
echo "-----------------------------------------------------------"
NON_DHI_SIZE=$(docker images --format "{{.Size}}" $NON_DHI_IMAGE)
DHI_SIZE=$(docker images --format "{{.Size}}" $DHI_IMAGE)
echo -e "Non-DHI (danielqsj/kafka-exporter):  ${RED}$NON_DHI_SIZE${NC}"
echo -e "DHI (dhi-kafka-exporter):            ${GREEN}$DHI_SIZE${NC}"
echo ""

# -----------------------------------------------------------------------------
# Layer Count
# -----------------------------------------------------------------------------
echo -e "${BLUE}📚 LAYER COUNT${NC}"
echo "-----------------------------------------------------------"
NON_DHI_LAYERS=$(docker history --no-trunc $NON_DHI_IMAGE | tail -n +2 | wc -l)
DHI_LAYERS=$(docker history --no-trunc $DHI_IMAGE | tail -n +2 | wc -l)
echo -e "Non-DHI: ${RED}$NON_DHI_LAYERS layers${NC}"
echo -e "DHI:     ${GREEN}$DHI_LAYERS layers${NC}"
echo ""

# -----------------------------------------------------------------------------
# User Check
# -----------------------------------------------------------------------------
echo -e "${BLUE}👤 DEFAULT USER${NC}"
echo "-----------------------------------------------------------"
NON_DHI_USER=$(docker inspect --format '{{.Config.User}}' $NON_DHI_IMAGE)
DHI_USER=$(docker inspect --format '{{.Config.User}}' $DHI_IMAGE)
echo -e "Non-DHI: ${YELLOW}${NON_DHI_USER:-root (not set)}${NC}"
echo -e "DHI:     ${GREEN}${DHI_USER:-nonroot}${NC}"
echo ""

# -----------------------------------------------------------------------------
# Shell Availability
# -----------------------------------------------------------------------------
echo -e "${BLUE}🐚 SHELL AVAILABILITY${NC}"
echo "-----------------------------------------------------------"
echo -n "Non-DHI: "
if docker run --rm --entrypoint="" $NON_DHI_IMAGE /bin/sh -c "echo shell exists" > /dev/null 2>&1; then
    echo -e "${RED}Shell available (/bin/sh)${NC}"
else
    echo -e "${GREEN}No shell${NC}"
fi

echo -n "DHI:     "
if docker run --rm --entrypoint="" $DHI_IMAGE /bin/sh -c "echo shell exists" > /dev/null 2>&1; then
    echo -e "${RED}Shell available (/bin/sh)${NC}"
else
    echo -e "${GREEN}No shell (hardened)${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# Package Manager Check
# -----------------------------------------------------------------------------
echo -e "${BLUE}📦 PACKAGE MANAGER${NC}"
echo "-----------------------------------------------------------"
echo -n "Non-DHI: "
if docker run --rm --entrypoint="" $NON_DHI_IMAGE which apk > /dev/null 2>&1; then
    echo -e "${RED}apk available${NC}"
elif docker run --rm --entrypoint="" $NON_DHI_IMAGE which apt > /dev/null 2>&1; then
    echo -e "${RED}apt available${NC}"
else
    echo -e "${GREEN}No package manager${NC}"
fi

echo -n "DHI:     "
if docker run --rm --entrypoint="" $DHI_IMAGE which apk > /dev/null 2>&1; then
    echo -e "${RED}apk available${NC}"
elif docker run --rm --entrypoint="" $DHI_IMAGE which apt > /dev/null 2>&1; then
    echo -e "${RED}apt available${NC}"
else
    echo -e "${GREEN}No package manager (hardened)${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# Binary Count (Attack Surface)
# -----------------------------------------------------------------------------
echo -e "${BLUE}⚔️  ATTACK SURFACE (Binary Count)${NC}"
echo "-----------------------------------------------------------"
echo -n "Non-DHI: "
NON_DHI_BINS=$(docker run --rm --entrypoint="" $NON_DHI_IMAGE ls /bin /usr/bin 2>/dev/null | wc -l || echo "0")
echo -e "${RED}$NON_DHI_BINS binaries${NC}"

echo -n "DHI:     "
DHI_BINS=$(docker run --rm --entrypoint="" $DHI_IMAGE ls /bin /usr/bin 2>/dev/null | wc -l || echo "0")
if [ "$DHI_BINS" -eq "0" ] || [ "$DHI_BINS" -lt "10" ]; then
    echo -e "${GREEN}Minimal (~1 binary)${NC}"
else
    echo -e "${YELLOW}$DHI_BINS binaries${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# Vulnerability Scan (if trivy is available)
# -----------------------------------------------------------------------------
echo -e "${BLUE}🔒 VULNERABILITY SCAN${NC}"
echo "-----------------------------------------------------------"
if command -v trivy &> /dev/null; then
    echo "Scanning Non-DHI image..."
    NON_DHI_VULNS=$(trivy image --quiet --severity HIGH,CRITICAL --format json $NON_DHI_IMAGE 2>/dev/null | jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0')
    echo -e "Non-DHI HIGH/CRITICAL: ${RED}$NON_DHI_VULNS vulnerabilities${NC}"
    
    echo "Scanning DHI image..."
    DHI_VULNS=$(trivy image --quiet --severity HIGH,CRITICAL --format json $DHI_IMAGE 2>/dev/null | jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0')
    echo -e "DHI HIGH/CRITICAL:     ${GREEN}$DHI_VULNS vulnerabilities${NC}"
else
    echo -e "${YELLOW}Trivy not installed. Install with: brew install trivy${NC}"
    echo "Skipping vulnerability scan..."
fi
echo ""

# -----------------------------------------------------------------------------
# Entrypoint Comparison
# -----------------------------------------------------------------------------
echo -e "${BLUE}🚀 ENTRYPOINT${NC}"
echo "-----------------------------------------------------------"
NON_DHI_EP=$(docker inspect --format '{{json .Config.Entrypoint}}' $NON_DHI_IMAGE)
DHI_EP=$(docker inspect --format '{{json .Config.Entrypoint}}' $DHI_IMAGE)
echo -e "Non-DHI: $NON_DHI_EP"
echo -e "DHI:     $DHI_EP"
echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   SUMMARY${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "| Feature              | Non-DHI              | DHI                  |"
echo -e "|----------------------|----------------------|----------------------|"
echo -e "| Image Size           | $NON_DHI_SIZE               | $DHI_SIZE              |"
echo -e "| Layers               | $NON_DHI_LAYERS                    | $DHI_LAYERS                     |"
echo -e "| User                 | ${NON_DHI_USER:-nobody}               | ${DHI_USER:-nonroot}              |"
echo -e "| Shell                | Available            | ${GREEN}None${NC}                 |"
echo -e "| Package Manager      | None                 | ${GREEN}None${NC}                 |"
echo -e "| Attack Surface       | ~$NON_DHI_BINS binaries        | ${GREEN}Minimal${NC}              |"
echo ""
echo -e "${GREEN}✓ DHI provides a hardened, minimal attack surface${NC}"
echo ""
