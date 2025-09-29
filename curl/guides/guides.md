## How to use this image

### Start a curl DHI container

Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```
# Using Alpine variant (recommended for minimal size)
$ docker run --rm <your-namespace>/dhi-curl:<tag>-alpine3.22 --version

# Using Debian variant (for compatibility)
$ docker run --rm <your-namespace>/dhi-curl:<tag> --version
```

## Common curl DHI use cases

### Basic HTTP requests

Execute simple HTTP requests:

```bash
# GET request (Alpine variant recommended for CI/CD)
$ docker run --rm dockerdevrel/dhi-curl:8.14.1-alpine3.22 https://api.github.com/repos/docker/cagent

# POST request with data
$ docker run --rm dockerdevrel/dhi-curl:8.14.1-alpine3.22 \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"key":"value"}' \
    https://api.github.com/repos/docker/cagent/issues
```

### File operations with volume mounts

Download files or work with local data:

```bash
# Upload file from host
mkdir -p /tmp/curl-dhi-file-test

# Create a simple test file
echo '{"project": "docker/cagent", "test": "upload", "timestamp": "'$(date)'"}' > /tmp/curl-dhi-file-test/upload-test.json

# Upload file to docker/cagent repository
docker run --rm -v /tmp/curl-dhi-file-test:/data dockerdevrel/dhi-curl:8.14.1-alpine3.22 \
    -X POST \
    -H "Content-Type: application/json" \
    -T /data/upload-test.json \
    https://api.github.com/repos/docker/cagent/issues

# Verify the file was created
ls -la /tmp/curl-dhi-file-test/
cat /tmp/curl-dhi-file-test/upload-test.json

# Cleanup
rm -rf /tmp/curl-dhi-file-test
```


### Multi-stage Dockerfile integration

**Important**: Curl DHI images are runtime-only variants. Curl DHI does not provide separate dev variants.

Here's a complete example for integration testing:

```dockerfile
# syntax=docker/dockerfile:1
# Development stage - Use standard curl for setup and testing
FROM curlimages/curl AS test-setup

WORKDIR /app

# Install testing tools and dependencies (standard image has package managers)
USER root
RUN apk add --no-cache jq bash

# Download docker/cagent configuration during build
RUN curl -o cagent-config.json https://raw.githubusercontent.com/docker/cagent/main/README.md || \
    echo '{"agent_name": "default", "project": "docker/cagent"}' > cagent-config.json

# Test docker/cagent repository availability during build
RUN curl --fail --silent https://api.github.com/repos/docker/cagent > /dev/null && \
    echo "docker/cagent repository accessible"

# Create a simple configuration file
RUN echo '{"curl_config": "production", "endpoints": ["docker/cagent", "docker/mcp-gateway"]}' > config.json

# Runtime stage - Curl DHI for production deployment
FROM dockerdevrel/dhi-curl:8.14.1-alpine3.22 AS runtime

WORKDIR /app

# Copy prepared configuration from setup stage
COPY --from=test-setup /app/config.json /app/config.json

# Default command to check docker/cagent status
CMD ["https://api.github.com/repos/docker/cagent"]
```

To build and test this:

```
# Build the multi-stage image
docker build -t my-curl-dhi-app .

# Run the application
docker run --rm my-curl-dhi-app

# Test with different endpoint
docker run --rm my-curl-dhi-app https://api.github.com/repos/docker/mcp-gateway
```


## Non-hardened images vs Docker Hardened Images

| Feature | Standard curl Images | Docker Hardened curl |
|---------|---------------------|---------------------|
| **Security** | Standard base with common utilities | Hardened base with reduced utilities |
| **Shell access** | Full shell access (bash/ash) | No shell access |
| **Package manager** | Full package managers (apk, apt) | System package managers removed |
| **User** | Runs as curl user or root | Runs as nonroot user |
| **Attack surface** | Full system utilities available | Significantly reduced |
| **System utilities** | Full system toolchain (ls, cat, id, ps, find, rm present) | Extremely minimal (ls, cat, id, ps, find, rm removed) |
| **Variants** | Multiple variants for different use cases | Runtime-only (no dev variants) |
| **SSL/TLS** | Full certificate management tools | Basic certificates included |



## Image variants

Docker Hardened curl images are runtime-only variants. It doesn't provide separate dev variants with additional development tools.

**Runtime variants** are designed to run curl commands in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Contain ONLY the curl binary (no shell, no system utilities)
- Support HTTP/HTTPS, FTP, and other protocols curl supports
- Require `docker debug` for any debugging needs

### Choosing between variants

**Alpine variants** (`8.14.1-alpine3.22`):
- **Pros**: Smallest size (~5MB), fastest downloads, ideal for CI/CD
- **Cons**: Limited system libraries, musl libc instead of glibc
- **Use when**: Bandwidth matters, simple HTTP operations, container orchestration

**Debian variants** (`8.14.1-debian13`):
- **Pros**: Better compatibility, glibc, more predictable behavior
- **Cons**: Larger size (~15MB), longer download times
- **Use when**: Complex applications, compatibility requirements, enterprise environments

## Migrate to a Docker Hardened Image

To migrate your curl deployment to Docker Hardened Images, you must update your deployment configuration and potentially your Dockerfile.

| Item | Migration note |
|------|----------------|
| **Base image** | Replace standard curl images with Docker Hardened curl images |
| **Package management** | System package managers removed (apk/apt removed) |
| **Protocol support** | Basic protocols supported, some advanced features may be limited |
| **Non-root user** | Runtime images run as nonroot user |
| **Multi-stage build** | Use standard curl images for setup stages and curl DHI for final deployment |
| **TLS certificates** | Standard certificates included |
| **File permissions** | Ensure mounted files are accessible to nonroot user |
| **System utilities** | Runtime images lack ALL system utilities (ls, cat, id, ps, find, rm removed) |
| **Shell access** | NO shell exists - cannot run shell commands or override entrypoint to shell |
| **Debugging** | Requires docker debug for any debugging needs | 



The following steps outline the general migration process.

1. Find hardened images for your app.

   A hardened image may have several variants. Inspect the image tags and find
   the image variant that meets your needs.

2. Update the base image in your Dockerfile.

   Update the base image in your application's Dockerfile to the hardened image
   you found in the previous step. For framework images, this is typically going
   to be an image tagged as `dev` because it has the tools needed to install
   packages and dependencies.

3. For multi-stage Dockerfiles, update the runtime image in your Dockerfile.

   To ensure that your final image is as minimal as possible, you should use a
   multi-stage build. All stages in your Dockerfile should use a hardened image.
   While intermediary stages will typically use images tagged as `dev`, your
   final runtime stage should use a non-dev image variant.

4. Install additional packages

   Docker Hardened Images contain minimal packages in order to reduce the
   potential attack surface. You may need to install additional packages in your
   Dockerfile. Inspect the image variants to identify which packages are already
   installed.

   Only images tagged as `dev` typically have package managers. You should use a
   multi-stage Dockerfile to install the packages. Install the packages in the
   build stage that uses a `dev` image. Then, if needed, copy any necessary
   artifacts to the runtime stage that uses a non-dev image.

   For Alpine-based images, you can use `apk` to install packages. For
   Debian-based images, you can use `apt-get` to install packages.

## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

Curl DHI runtime images contain basic shell access but lack most system utilities for debugging. Common commands like `ls`, `cat`, `id`, `ps`, `find`, and `rm` are removed. The recommended method for debugging applications built with Docker Hardened Images is to use `docker debug` to attach to these containers.

### Permissions

By default image variants intended for runtime, run as the nonroot user. Ensure
that necessary files and directories are accessible to the nonroot user. You may
need to copy files to different directories or change permissions so your
application running as the nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result,
applications in these images can't bind to privileged ports (below 1024) when
running in Kubernetes or in Docker Engine versions older than 20.10. To avoid
issues, configure your application to listen on port 1025 or higher inside the
container, even if you map it to a lower port on the host. For example, `docker
run -p 80:8080 my-image` will work because the port inside the container is 8080,
and `docker run -p 80:81 my-image` won't work because the port inside the
container is 81.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev`
images in build stages to run shell commands and then copy any necessary
artifacts into the runtime stage. In addition, use Docker Debug to debug
containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as
Docker Official Images. Use `docker inspect` to inspect entry points for Docker
Hardened Images and update your Dockerfile if necessary.
