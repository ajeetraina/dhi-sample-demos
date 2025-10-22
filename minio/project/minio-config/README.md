# MinIO Configuration Directory

This directory contains configuration files that will be copied to the
MinIO Docker Hardened Image during the build process.

## Files:

- **app-config.json**: Application-level configuration
- **policies.json**: IAM policies for bucket access
- **regions.json**: Region configuration
- **compression.json**: Compression settings

## Build Process:

1. Setup stage: Files are copied to /app/config/
2. Runtime stage: Files are copied to /etc/minio/
3. MinIO reads configuration from /etc/minio/ at runtime

## Security Note:

Do not include sensitive credentials in these files.
Use environment variables for secrets (MINIO_ROOT_USER, MINIO_ROOT_PASSWORD).
