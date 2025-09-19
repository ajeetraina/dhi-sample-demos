# How to use this image
Refer to the LocalStack documentation for configuring LocalStack for your project's needs.

## Start a LocalStack instance
To start a LocalStack instance, run the following command. Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```bash
$ docker run -d -p 4566:4566 -p 5678:5678 -p 4510-4559:4510-4559 <your-namespace>/dhi-localstack:<tag>
```

**Important**: LocalStack DHI images use `localstack-supervisor` as their ENTRYPOINT. The container starts LocalStack services automatically and listens on the configured ports.

**Test the LocalStack instance**: Use the health endpoint to verify LocalStack is running:

```bash
$ curl -f http://localhost:4566/_localstack/health
```

## Common LocalStack use cases

### Run LocalStack for development
Start LocalStack with specific AWS services enabled:

```bash
$ docker run -d -p 4566:4566 \
    -e SERVICES=s3,dynamodb,lambda,sqs \
    <your-namespace>/dhi-localstack:<tag>

# Test that services are available
$ curl -f http://localhost:4566/_localstack/health
```

### Run LocalStack with persistence
Enable data persistence across container restarts:

```bash
$ docker run -d -p 4566:4566 \
    -e PERSISTENCE=1 \
    -v localstack-data:/var/lib/localstack \
    <your-namespace>/dhi-localstack:<tag>

# Verify LocalStack is running with persistence enabled
$ curl -f http://localhost:4566/_localstack/health
```

### Integration testing with multi-stage Dockerfile
**Important**: LocalStack Docker Hardened Images come in both runtime and dev variants. Runtime variants are optimized for production deployment, while dev variants include additional tools for development and testing.

Here's a complete example for integration testing:

```dockerfile
# syntax=docker/dockerfile:1
# Development stage - LocalStack DHI dev for testing setup
FROM <your-namespace>/dhi-localstack:<tag>-dev AS test-setup

WORKDIR /app

# Install testing tools and dependencies
RUN apk add --no-cache curl jq aws-cli

# Copy test scripts and configuration
COPY test-scripts/ ./test-scripts/
COPY localstack-config/ ./config/

# Runtime stage - LocalStack DHI for running services
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
| Shell access | Direct shell access | No shell access (runtime), full shell access (dev) |
| Package manager | Full package managers (apt, pip) | No package managers (runtime only) |
| User | Runs as root by default | Runs as nonroot user (runtime) |
| Attack surface | Large (300+ utilities, full Ubuntu/Debian) | Minimal (150 utilities, 50% fewer than standard) |
| Runtime variants | Single variant for all use cases | Separate runtime and dev variants |
| Debugging | Traditional shell debugging | Use Docker Debug or dev variant |
| Utilities | Full development toolchain (curl, wget, git, vim, nano) | Minimal utilities (no curl, wget, git, vim, nano) |

## Why such extreme minimization?
Docker Hardened LocalStack images prioritize security through strategic minimalism:

- **Complete package manager removal**: Runtime images cannot install additional software during execution
- **Utility reduction**: 50% fewer binaries than standard images (150 vs 300+)
- **Custom hardened OS**: Purpose-built "Docker Hardened Images (Debian)" not standard distributions
- **Essential-only toolset**: Only LocalStack core, Python runtime, and essential AWS service libraries included

The hardened runtime images focus exclusively on providing a secure, minimal LocalStack execution environment. Development and debugging tasks use the dev variants with additional tools.

## Image variants
Docker Hardened Images come in different variants depending on their intended use.

**Runtime variants** are designed to run LocalStack in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:
- Run as the nonroot user
- Do not include a shell or a package manager  
- Contain only the minimal set of libraries needed to run LocalStack

**Build-time variants** typically include `dev` in the variant name and are intended for use in development and testing. These images typically:
- Run as the root user
- Include a shell and package manager
- Are used for development, testing, and debugging

### Available variants
LocalStack DHI images follow this tag pattern: `<localstack-version>` for runtime and `<localstack-version>-dev` for development.

**LocalStack versions:**
- `4.8.1` - Specific patch version (recommended for production)
- `4.8` - Latest patch of 4.8 series
- `4` - Latest minor and patch version
- `latest` - Latest stable release

## Migrate to a Docker Hardened Image
To migrate your LocalStack deployment to Docker Hardened Images, you must update your deployment configuration and potentially your Dockerfile.

| Item | Migration note |
|------|----------------|
| Base image | Replace LocalStack base images with Docker Hardened LocalStack images |
| Package management | Runtime images don't contain package managers. Use dev images for development tasks |
| Non-root user | Runtime images run as nonroot user. Ensure mounted files are accessible to nonroot user |
| Multi-stage build | Use dev images for setup stages and runtime images for final deployment |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default |
| Ports | Applications run as nonroot user, but LocalStack is pre-configured for correct ports |
| Entry point | Images use `localstack-supervisor` as ENTRYPOINT |
| No shell | Runtime images don't contain shell. Use dev images or Docker Debug for debugging |

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

### Permissions  
By default, runtime image variants run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so LocalStack running as the nonroot user can access them.

### Privileged ports
Runtime hardened images run as a nonroot user by default. LocalStack is pre-configured to use non-privileged ports (4566, 5678, 4510-4559), so this should not be an issue. However, if you customize LocalStack to use privileged ports (below 1024), it won't work in Kubernetes or Docker Engine versions older than 20.10.

### No shell
By default, runtime image variants don't contain a shell. Use dev images for development tasks that require shell access, then deploy with runtime images. Use Docker Debug to debug containers with no shell.

### Entry point
Docker Hardened LocalStack images use `localstack-supervisor` as the entry point, which may differ from other LocalStack distributions. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your deployment configuration if necessary.
