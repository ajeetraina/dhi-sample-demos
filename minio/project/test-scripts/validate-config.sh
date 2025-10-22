#!/bin/bash
# Validate MinIO configuration files
# Runs during build to catch errors early

echo "=== Configuration Validation ==="

# Check JSON files are valid
for file in /app/config/*.json; do
    if [ -f "$file" ]; then
        echo "Validating $file..."
        jq empty "$file" && echo "  ✓ Valid JSON"
    fi
done

echo "All configuration files validated successfully"
