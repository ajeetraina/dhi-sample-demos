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
Enable data persistence across container restarts:

```bash
$ docker volume create localstack-data
$ docker run -d -p 4566:4566 \
    -e PERSISTENCE=1 \
    -v localstack-data:/var/lib/localstack \
    <your-namespace>/dhi-localstack:<tag>

# Verify LocalStack is running with persistence enabled
$ curl -f http://localhost:4566/_localstack/health
```

### Integration testing with multi-stage Dockerfile
**Important**: LocalStack Docker Hardened Images are runtime-only variants. Unlike other DHI products (like Maven), LocalStack DHI does not provide separate dev variants with additional tools.

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

### Run with custom configuration
Use environment variables and mounted configuration:

```bash
# Create a persistent volume for LocalStack data
$ docker volume create localstack-data

# Use the volume for persistent data across restarts
$ docker run -d \
    -p 4566:4566 -p 5678:5678 \
    -e DEBUG=1 \
    -e SERVICES=s3,dynamodb,sqs,sns \
    -v localstack-data:/var/lib/localstack \
    <your-namespace>/dhi-localstack:<tag>
```

**Note**: The first startup initializes services (~3-5 seconds), while subsequent startups with persistence are faster (~1-2 seconds).

You can then test LocalStack services:

```bash
$ curl -f http://localhost:4566/_localstack/health
$ aws --endpoint-url=http://localhost:4566 s3 mb s3://test-bucket
```

## Non-hardened images vs Docker Hardened Images

| Feature | Docker Official LocalStack | Docker Hardened LocalStack |
|---------|----------------------------|----------------------------|
| Security | Standard base with common utilities | Custom hardened Debian with security patches |
| Shell access | Direct shell access | Basic shell access |
| Package manager | Full package managers (apt, pip) | No package managers |
| User | Runs as root by default | Runs as nonroot user |
| Attack surface | Large (300+ utilities, full Ubuntu/Debian) | Minimal (50+ utilities, 85% fewer than standard) |
| Service compatibility | All LocalStack services supported | Limited service support (see service limitations) |
| Java services | DynamoDB, Lambda work out of box | Java services may fail due to missing dependencies |
| Debugging | Traditional shell debugging | Basic shell available or use Docker Debug |
| System utilities | Full system toolchain (id, ps, top, find, rm) | Extremely minimal (no id, ps, top, find, rm) |
| Variants | Single variant for all use cases | Runtime-only (no dev variants) |

## Why such extreme minimization?
Docker Hardened LocalStack images prioritize security through aggressive minimalism:

- **Complete package manager removal**: Runtime images cannot install additional software during execution
- **Utility reduction**: 85% fewer binaries than standard images (50+ vs 300+)
- **Custom hardened OS**: Purpose-built "Docker Hardened Images (Debian)" not standard distributions  
- **Essential-only toolset**: Only LocalStack core, Python runtime, and essential AWS service libraries included

The hardened runtime images focus exclusively on providing a secure, minimal LocalStack execution environment while maintaining basic shell access for debugging. Development and testing tasks use the dev variants with additional tools.

## Image variants
Docker Hardened LocalStack images are **runtime-only variants**. Unlike other DHI products (such as Maven), LocalStack DHI does not provide separate dev variants with additional development tools.

**Runtime variants** are designed to run LocalStack in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:
- Run as the nonroot user
- Include basic shell but no package manager  
- Contain only the minimal set of libraries needed to run LocalStack

### Available variants
LocalStack DHI images follow this tag pattern: `<localstack-version>-<python-version>-<os>`. All available tags are runtime variants.

**LocalStack versions:**
- `4.8.1` - Specific patch version (recommended for production)
- `4.8` - Latest patch of 4.8 series
- `4` - Latest minor and patch version

**Python versions:**
- `python3.12` - Python 3.12 (recommended for new deployments)
- `python3.11` - Python 3.11 (stable)
- `python3.10` - Python 3.10 (legacy support)

**Operating systems:**
- `debian13` - Debian-based (default, ~115MB compressed)
- `alpine3.22` - Alpine-based (if available, smaller footprint)

**Note**: Multiple tag combinations may point to the same underlying image for organizational clarity.

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
