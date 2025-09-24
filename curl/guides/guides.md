## How to use this image

### Start a curl DHI container

Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```
$ docker run --rm dockerdevrel/dhi-curl:8.14.1-alpine3.22 --version
```

## Common curl DHI use cases

### Basic HTTP requests


Run a container to fetch website headers

```
$ docker run --rm <your-namespace>/dhi-curl:<tag> -I https://www.docker.com
```

### File operations with volume mounts

Download files or work with local data:

```bash
# Download file to host
$ docker run --rm -v $(pwd):/data dockerdevrel/dhi-curl:8.14.1-alpine3.22 \
    -o /data/downloaded-file.txt \
    https://example.com/file.txt

# Upload file from host
$ docker run --rm -v $(pwd):/data dockerdevrel/dhi-curl:8.14.1-alpine3.22 \
    -X PUT \
    -T /data/upload-file.txt \
    https://httpbin.org/put
```

### Integration in CI/CD pipelines

Use curl DHI for health checks and API testing:

```bash
# Health check with retry logic (Alpine variant saves bandwidth)
$ docker run --rm dockerdevrel/dhi-curl:8.14.1-alpine3.22 \
    --retry 5 \
    --retry-delay 2 \
    --fail \
    https://my-service.com/health
```

### Multi-stage Dockerfile integration

**Important**: Curl DHI images are runtime-only variants. Curl DHI does not provide separate dev variants.

Here's a complete example for integration testing:

```dockerfile
# syntax=docker/dockerfile:1
# Development stage - Use standard curl for testing setup
FROM curlimages/curl AS test-setup

WORKDIR /app

# Install testing tools and dependencies (standard image has package managers)
USER root
RUN apk add --no-cache jq bash

# Copy test scripts and configuration
COPY test-scripts/ ./test-scripts/
COPY curl-config/ ./config/

# Runtime stage - Curl DHI for production deployment
FROM dockerdevrel/dhi-curl:8.14.1-alpine3.22 AS runtime

WORKDIR /app
COPY --from=test-setup /app/config/ /etc/curl/

# Use default curl DHI entrypoint
```

### Choosing between variants

**Alpine variants** (`8.14.1-alpine3.22`):
- **Pros**: Smallest size (~5MB), fastest downloads, ideal for CI/CD
- **Cons**: Limited system libraries, musl libc instead of glibc
- **Use when**: Bandwidth matters, simple HTTP operations, container orchestration

**Debian variants** (`8.14.1-debian13`):
- **Pros**: Better compatibility, glibc, more predictable behavior
- **Cons**: Larger size (~15MB), longer download times
- **Use when**: Complex applications, compatibility requirements, enterprise environments

## Non-hardened images vs Docker Hardened Images

| Feature | Standard curl Images | Docker Hardened curl |
|---------|---------------------|---------------------|
| **Security** | Standard base with common utilities | Hardened base with reduced utilities |
| **Shell access** | Full shell access (bash/ash) | Basic shell access (sh) |
| **Package manager** | Full package managers (apk, apt) | System package managers removed |
| **User** | Runs as curl user or root | Runs as nonroot user |
| **Attack surface** | Full system utilities available | Significantly reduced |
| **System utilities** | Full system toolchain (ls, cat, id, ps, find, rm present) | Extremely minimal (ls, cat, id, ps, find, rm removed) |
| **Variants** | Multiple variants for different use cases | Runtime-only (no dev variants) |
| **SSL/TLS** | Full certificate management tools | Basic certificates included |


## Image variants

Docker Hardened curl images are runtime-only variants. Unlike other DHI products, curl DHI does not provide separate dev variants with additional development tools.

**Runtime variants** are designed to run curl commands in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Include basic shell with system package managers removed
- Contain only the minimal set of libraries needed to run curl
- Support HTTP/HTTPS, FTP, and other protocols curl supports

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
| **System utilities** | Runtime images lack most system utilities (ls, cat, id, ps, find, rm removed) |


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
