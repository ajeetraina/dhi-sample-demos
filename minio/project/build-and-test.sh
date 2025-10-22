#!/bin/bash
set -e

echo "=== MinIO Multi-Stage Build and Test ==="

# Build
echo "Building image..."
docker build -t minio-custom:latest .

# Run
echo "Starting container..."
docker run -d --name minio-test \
    -p 9000:9000 -p 9001:9001 \
    minio-custom:latest

# Wait
echo "Waiting for startup..."
sleep 15

# Test
echo "Testing health..."
curl -f http://localhost:9000/minio/health/live && echo "✓ Health check passed"

echo "Testing S3..."
export AWS_ACCESS_KEY_ID=admin
export AWS_SECRET_ACCESS_KEY=password123
aws --endpoint-url=http://localhost:9000 s3 mb s3://test-bucket
aws --endpoint-url=http://localhost:9000 s3 ls

echo ""
echo "✅ All tests passed!"
echo "Console: http://localhost:9001"
echo "Credentials: admin / password123"
