#!/bin/bash
# Health check script for MinIO
# This would be used in the setup stage for testing

echo "=== MinIO Health Check ==="
echo "Checking MinIO health endpoint..."

if curl -f http://localhost:9000/minio/health/live 2>/dev/null; then
    echo "✓ MinIO is healthy"
    exit 0
else
    echo "✗ MinIO health check failed"
    exit 1
fi
