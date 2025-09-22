# How to use this image
Refer to the LocalStack documentation for configuring LocalStack for your project's needs.

## Start a LocalStack instance
To start a LocalStack instance, run the following command. Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```bash
$ docker run -d -p 4566:4566 -p 5678:5678 -p 4510-4559:4510-4559 <your-namespace>/dhi-localstack:<tag>
```

**Test the LocalStack instance**: Use the health endpoint to verify LocalStack is running:

```bash
$ curl -f http://localhost:4566/_localstack/health
```

**Note**: Some services may require additional initialization time. If a service shows "available" in health check but connection fails, wait 10-15 seconds and retry.

## Common LocalStack use cases

### Run LocalStack for development
Start LocalStack with specific AWS services enabled:

```bash
$ docker run -d -p 4566:4566 \
    -e SERVICES=s3,sqs,sns,sts,iam,secretsmanager,ssm \
    <your-namespace>/dhi-localstack:<tag>

# Test that services are available
$ curl -f http://localhost:4566/_localstack/health
```


### Run LocalStack with persistence

This example demonstrates how to enable data persistence in LocalStack, which means your AWS service data (S3 buckets, SQS queues, etc.) will survive container restarts instead of being lost each time. The setup requires creating a Docker volume (localstack-data) and mounting it to LocalStack's data directory (`/var/lib/localstack`) while setting the `PERSISTENCE=1` environment variable. This tells LocalStack to save all service data to the mounted volume instead of keeping it only in memory.

Enable data persistence across container restarts:


```
# create a volume
$ docker volume create localstack-data
$ docker run -d --name ls-persist-test \
    -p 4566:4566 \
    -e PERSISTENCE=1 \
    -v localstack-data:/var/lib/localstack \
    <your-namespace>/dhi-localstack:<tag>

# Step 2: Verify LocalStack is running
$ curl -f http://localhost:4566/_localstack/health

# Create test data
aws --endpoint-url=http://localhost:4566 s3 mb s3://persistence-test-bucket
aws --endpoint-url=http://localhost:4566 s3 cp /etc/hosts s3://persistence-test-bucket/test-file.txt

# Verify data exists
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 s3 ls s3://persistence-test-bucket

# Start new container with same volume
docker run -d --name ls-persist-test2 \
    -p 4566:4566 \
    -e PERSISTENCE=1 \
    -v localstack-data:/var/lib/localstack \
    <your-namespace>/dhi-localstack:<tag>


# Verify data persisted
echo "Data after restart:"
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 s3 ls s3://persistence-test-bucket
```

### Integration testing with multi-stage Dockerfile
**Important**: LocalStack Docker Hardened Images are runtime-only variants. LocalStack DHI does not provide separate dev variants.

Here's a complete example for integration testing:

```dockerfile
# syntax=docker/dockerfile:1
# Development stage - Use standard LocalStack for testing setup
FROM localstack/localstack AS test-setup

WORKDIR /app

# Install testing tools and dependencies (standard image has package managers)
RUN apt-get update && apt-get install -y curl jq aws-cli

# Copy test scripts and configuration
COPY test-scripts/ ./test-scripts/
COPY localstack-config/ ./config/

# Runtime stage - LocalStack DHI for production deployment
FROM <your-namespace>/dhi-localstack:<tag> AS runtime

WORKDIR /app
COPY --from=test-setup /app/config/ /etc/localstack/

EXPOSE 4566 5678 4510-4559
# Use default LocalStack entrypoint
```


## Non-hardened images vs Docker Hardened Images

| Feature | Docker Official LocalStack | Docker Hardened LocalStack |
|---------|----------------------------|----------------------------|
| Security | Standard base with common utilities | Hardened base with reduced utilities |
| Shell access | Direct shell access (bash) | Basic shell access (sh) |
| Package manager | Full package managers (apt, pip) | System package managers removed (apt removed, pip retained) |
| User | Runs as root by default | Runs as nonroot user |
| Attack surface | Full system utilities available | Significantly reduced (tested utilities removed) |
| System utilities | Full system toolchain (ls, cat, id, ps, find, rm all present) | Extremely minimal (ls, cat, id, ps, find, rm all removed) |
| Variants | Single variant for all use cases | Runtime-only (no dev variants) |


## Image variants
Docker Hardened LocalStack images are **runtime-only variants**. Unlike other DHI products (such as Maven), LocalStack DHI does not provide separate dev variants with additional development tools.

**Runtime variants** are designed to run LocalStack in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:
- Run as the nonroot user
- Include basic shell with system package managers removed (pip retained for LocalStack functionality)  
- Contain only the minimal set of libraries needed to run LocalStack

## Migrate to a Docker Hardened Image
To migrate your LocalStack deployment to Docker Hardened Images, you must update your deployment configuration and potentially your Dockerfile.

| Item | Migration note |
|------|----------------|
| Base image | Replace LocalStack base images with Docker Hardened LocalStack images |
| Package management | Runtime images don't contain package managers |
| Service dependencies | Some services (DynamoDB, Lambda) may not work due to missing Java dependencies |
| Non-root user | Runtime images run as nonroot user. Ensure mounted files are accessible to nonroot user |
| Multi-stage build | Use standard LocalStack images for setup stages and LocalStack DHI for final deployment |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default |
| Ports | Applications run as nonroot user, but LocalStack is pre-configured for correct ports |
| Entry point | Images use `localstack-supervisor` as ENTRYPOINT |
| System utilities | Runtime images lack most system utilities (id, ps, top, find, rm) |

## Migration process

### 1. Identify your deployment requirements
Choose the appropriate LocalStack DHI variant based on your needs:
- **Runtime variant**: For production deployments, CI/CD pipelines, testing environments
- **Dev variant**: For development, debugging, custom tooling integration

### 2. Update container deployment
Update your container run commands or docker-compose files:

```bash
# Before (standard LocalStack)
docker run -d -p 4566:4566 localstack/localstack

# After (runtime hardened)
docker run -d -p 4566:4566 <your-namespace>/dhi-localstack:<tag>
```

### 3. Handle file permissions for mounted volumes
Ensure mounted directories are accessible to the nonroot user:

```bash
# Set appropriate permissions for persistent data
chmod -R 755 ./localstack-data
chown -R 65532:65532 ./localstack-data

# Use in docker run
docker run -d -p 4566:4566 \
    -v ./localstack-data:/var/lib/localstack \
    <your-namespace>/dhi-localstack:<tag>
```

### 4. Use multi-stage builds for custom integrations
When you need to customize LocalStack setup:

```dockerfile
# Setup stage
FROM <your-namespace>/dhi-localstack:<tag>-dev AS setup
RUN apk add --no-cache curl
COPY setup-scripts/ /opt/setup/
RUN /opt/setup/configure-localstack.sh

# Runtime stage  
FROM <your-namespace>/dhi-localstack:<tag> AS runtime
COPY --from=setup /etc/localstack/ /etc/localstack/
EXPOSE 4566
```

## Troubleshooting migration
The following are common issues that you may encounter during migration.

### General debugging
The hardened runtime images don't contain a shell or debugging tools. The recommended method for debugging LocalStack containers built with Docker Hardened Images is to use Docker Debug to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Service dependencies and limitations
LocalStack DHI has significant service limitations due to extreme minimization:

```bash
# Services that work reliably
SERVICES=s3,sqs,sns,sts,iam,secretsmanager,ssm

# Services that typically fail due to Java dependencies
SERVICES=dynamodb,lambda,elasticsearch,kinesis
```

**Java-dependent services**: DynamoDB, Lambda, and other services require Java runtime installation, which fails due to missing system utilities (`rm`, `objcopy`, etc.). 

**No workaround available**: Unlike other DHI products, LocalStack does not provide dev variants that include these dependencies.

**Recommendation**: Use LocalStack DHI only for Python-based services (S3, SQS, etc.). For comprehensive LocalStack testing including Java services, use standard LocalStack images.

### Missing system utilities
The hardened image lacks most system utilities that some services need:

```bash
# Missing utilities cause service failures
- rm, cp, mv (file operations for Java installation)
- objcopy (from binutils, needed for Java linking)  
- tar, gzip (archive utilities for dependency downloads)
- id, ps, top, find (system inspection tools)
```

**Impact**: Services requiring these utilities for initialization will fail with "command not found" errors.

**Solution**: Consider LocalStack DHI a **specialized tool for core AWS services only**, not a complete LocalStack replacement.

### Service initialization timing
Some LocalStack services may require additional time to fully initialize even after showing "available" in the health endpoint. If you receive connection refused errors:

```bash
# Check service status
curl -f http://localhost:4566/_localstack/health | jq '.services'

# Check container logs for dependency issues
docker logs <container-id> | grep -E "(ERROR|WARN|Installation.*failed)"

# Wait 10-15 seconds and retry the operation
# Services typically initialize within 15-30 seconds after container start
```

**Note**: If you see "command not found" errors in logs for `rm`, `objcopy`, or other system utilities, the service requires dependencies not available in the hardened image. This is a fundamental limitation - no dev variant exists to provide these dependencies.

**Recommendation**: For applications requiring Java-dependent services, consider:
1. Using standard LocalStack images for full service compatibility
2. Using LocalStack DHI only for specific Python-based services (S3, SQS, etc.)
3. Hybrid approach: LocalStack DHI for core services + standard LocalStack for Java services

### Permissions  
By default, runtime image variants run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so LocalStack running as the nonroot user can access them.

### Privileged ports
Runtime hardened images run as a nonroot user by default. LocalStack is pre-configured to use non-privileged ports (4566, 5678, 4510-4559), so this should not be an issue. However, if you customize LocalStack to use privileged ports (below 1024), it won't work in Kubernetes or Docker Engine versions older than 20.10.

### No shell
Runtime image variants contain basic shell access but lack most system utilities. Since LocalStack DHI only provides runtime variants, use multi-stage builds with standard LocalStack images for development tasks that require full shell capabilities and system tools, then deploy with runtime images. Use Docker Debug for advanced debugging with additional tools.

### Entry point
Docker Hardened LocalStack images use `localstack-supervisor` as the entry point, which may differ from other LocalStack distributions. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your deployment configuration if necessary.
