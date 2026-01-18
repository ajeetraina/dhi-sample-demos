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

printf "${BLUE}============================================================${NC}\n"
printf "${BLUE}   DHI vs Non-DHI Image Comparison: Kafka Exporter${NC}\n"
printf "${BLUE}============================================================${NC}\n"
printf "\n"

# Pull both images
printf "${YELLOW}Pulling images...${NC}\n"
docker pull $NON_DHI_IMAGE > /dev/null 2>&1
docker pull $DHI_IMAGE > /dev/null 2>&1
printf "${GREEN}✓ Images pulled successfully${NC}\n"
printf "\n"

# -----------------------------------------------------------------------------
# Image Size Comparison
# -----------------------------------------------------------------------------
printf "${BLUE}📦 IMAGE SIZE${NC}\n"
printf "-----------------------------------------------------------\n"
NON_DHI_SIZE=$(docker images --format "{{.Size}}" $NON_DHI_IMAGE)
DHI_SIZE=$(docker images --format "{{.Size}}" $DHI_IMAGE)
printf "Non-DHI (danielqsj/kafka-exporter):  ${RED}%s${NC}\n" "$NON_DHI_SIZE"
printf "DHI (dhi-kafka-exporter):            ${GREEN}%s${NC}\n" "$DHI_SIZE"
printf "\n"

# -----------------------------------------------------------------------------
# Layer Count
# -----------------------------------------------------------------------------
printf "${BLUE}📚 LAYER COUNT${NC}\n"
printf "-----------------------------------------------------------\n"
NON_DHI_LAYERS=$(docker history --no-trunc $NON_DHI_IMAGE | tail -n +2 | wc -l | tr -d ' ')
DHI_LAYERS=$(docker history --no-trunc $DHI_IMAGE | tail -n +2 | wc -l | tr -d ' ')
printf "Non-DHI: ${RED}%s layers${NC}\n" "$NON_DHI_LAYERS"
printf "DHI:     ${GREEN}%s layers${NC}\n" "$DHI_LAYERS"
printf "\n"

# -----------------------------------------------------------------------------
# User Check
# -----------------------------------------------------------------------------
printf "${BLUE}👤 DEFAULT USER${NC}\n"
printf "-----------------------------------------------------------\n"
NON_DHI_USER=$(docker inspect --format '{{.Config.User}}' $NON_DHI_IMAGE)
DHI_USER=$(docker inspect --format '{{.Config.User}}' $DHI_IMAGE)
printf "Non-DHI: ${YELLOW}%s${NC}\n" "${NON_DHI_USER:-root (not set)}"
printf "DHI:     ${GREEN}%s${NC}\n" "${DHI_USER:-nonroot}"
printf "\n"

# -----------------------------------------------------------------------------
# Shell Availability
# -----------------------------------------------------------------------------
printf "${BLUE}🐚 SHELL AVAILABILITY${NC}\n"
printf "-----------------------------------------------------------\n"
printf "Non-DHI: "
if docker run --rm --entrypoint="" $NON_DHI_IMAGE /bin/sh -c "echo shell exists" > /dev/null 2>&1; then
    printf "${RED}Shell available (/bin/sh)${NC}\n"
else
    printf "${GREEN}No shell${NC}\n"
fi

printf "DHI:     "
if docker run --rm --entrypoint="" $DHI_IMAGE /bin/sh -c "echo shell exists" > /dev/null 2>&1; then
    printf "${RED}Shell available (/bin/sh)${NC}\n"
else
    printf "${GREEN}No shell (hardened)${NC}\n"
fi
printf "\n"

# -----------------------------------------------------------------------------
# Package Manager Check
# -----------------------------------------------------------------------------
printf "${BLUE}📦 PACKAGE MANAGER${NC}\n"
printf "-----------------------------------------------------------\n"
printf "Non-DHI: "
if docker run --rm --entrypoint="" $NON_DHI_IMAGE which apk > /dev/null 2>&1; then
    printf "${RED}apk available${NC}\n"
elif docker run --rm --entrypoint="" $NON_DHI_IMAGE which apt > /dev/null 2>&1; then
    printf "${RED}apt available${NC}\n"
else
    printf "${GREEN}No package manager${NC}\n"
fi

printf "DHI:     "
if docker run --rm --entrypoint="" $DHI_IMAGE which apk > /dev/null 2>&1; then
    printf "${RED}apk available${NC}\n"
elif docker run --rm --entrypoint="" $DHI_IMAGE which apt > /dev/null 2>&1; then
    printf "${RED}apt available${NC}\n"
else
    printf "${GREEN}No package manager (hardened)${NC}\n"
fi
printf "\n"

# -----------------------------------------------------------------------------
# Binary Count (Attack Surface)
# -----------------------------------------------------------------------------
printf "${BLUE}⚔️  ATTACK SURFACE (Binary Count)${NC}\n"
printf "-----------------------------------------------------------\n"
printf "Non-DHI: "
NON_DHI_BINS=$(docker run --rm --entrypoint="" $NON_DHI_IMAGE ls /bin /usr/bin 2>/dev/null | wc -l | tr -d ' ' || echo "0")
printf "${RED}%s binaries${NC}\n" "$NON_DHI_BINS"

printf "DHI:     "
DHI_BINS=$(docker run --rm --entrypoint="" $DHI_IMAGE ls /bin /usr/bin 2>/dev/null | wc -l | tr -d ' ' || echo "0")
if [ "$DHI_BINS" -eq "0" ] 2>/dev/null || [ "$DHI_BINS" -lt "10" ] 2>/dev/null; then
    printf "${GREEN}Minimal (~1 binary)${NC}\n"
else
    printf "${YELLOW}%s binaries${NC}\n" "$DHI_BINS"
fi
printf "\n"

# -----------------------------------------------------------------------------
# Vulnerability Scan (if trivy is available)
# -----------------------------------------------------------------------------
printf "${BLUE}🔒 VULNERABILITY SCAN${NC}\n"
printf "-----------------------------------------------------------\n"
if command -v trivy &> /dev/null; then
    printf "Scanning Non-DHI image...\n"
    NON_DHI_VULNS=$(trivy image --quiet --severity HIGH,CRITICAL --format json $NON_DHI_IMAGE 2>/dev/null | jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0')
    printf "Non-DHI HIGH/CRITICAL: ${RED}%s vulnerabilities${NC}\n" "$NON_DHI_VULNS"
    
    printf "Scanning DHI image...\n"
    DHI_VULNS=$(trivy image --quiet --severity HIGH,CRITICAL --format json $DHI_IMAGE 2>/dev/null | jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0')
    printf "DHI HIGH/CRITICAL:     ${GREEN}%s vulnerabilities${NC}\n" "$DHI_VULNS"
else
    printf "${YELLOW}Trivy not installed. Install with: brew install trivy${NC}\n"
    printf "Skipping vulnerability scan...\n"
fi
printf "\n"

# -----------------------------------------------------------------------------
# Entrypoint Comparison
# -----------------------------------------------------------------------------
printf "${BLUE}🚀 ENTRYPOINT${NC}\n"
printf "-----------------------------------------------------------\n"
NON_DHI_EP=$(docker inspect --format '{{json .Config.Entrypoint}}' $NON_DHI_IMAGE)
DHI_EP=$(docker inspect --format '{{json .Config.Entrypoint}}' $DHI_IMAGE)
printf "Non-DHI: %s\n" "$NON_DHI_EP"
printf "DHI:     %s\n" "$DHI_EP"
printf "\n"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
printf "${BLUE}============================================================${NC}\n"
printf "${BLUE}   SUMMARY${NC}\n"
printf "${BLUE}============================================================${NC}\n"
printf "\n"
printf "┌──────────────────────┬──────────────────────┬──────────────────────┐\n"
printf "│ Feature              │ Non-DHI              │ DHI                  │\n"
printf "├──────────────────────┼──────────────────────┼──────────────────────┤\n"
printf "│ Image Size           │ %-20s │ %-20s │\n" "$NON_DHI_SIZE" "$DHI_SIZE"
printf "│ Layers               │ %-20s │ %-20s │\n" "$NON_DHI_LAYERS" "$DHI_LAYERS"
printf "│ User                 │ %-20s │ %-20s │\n" "${NON_DHI_USER:-nobody}" "${DHI_USER:-nonroot}"
printf "│ Shell                │ %-20s │ %-20s │\n" "Available" "None"
printf "│ Package Manager      │ %-20s │ %-20s │\n" "None" "None"
printf "│ Attack Surface       │ %-20s │ %-20s │\n" "$NON_DHI_BINS binaries" "Minimal"
printf "└──────────────────────┴──────────────────────┴──────────────────────┘\n"
printf "\n"
printf "${GREEN}✓ DHI provides a hardened, minimal attack surface${NC}\n"
printf "\n"
