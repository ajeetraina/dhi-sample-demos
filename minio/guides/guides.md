## How to use this image

### Start an MinIO instance

To start a MinIO instance, run the following command. Replace `<your-namespace>` with your organization's namespace and
`<tag>` with the image variant you want to run.

```
$ docker run -p 9000:9000 <your-namespace>/dhi-minio:<tag>
```

To start a MinIO instance with the Console (Web UI) run:

```
$ docker run -p 9000:9000 -p 9001:9001 <your-namespace>/dhi-minio:<tag> server --console-address=":9001"
```

- Port 9000 - API endpoint (health checks work here)
- Port 9001 - Web Console (HTML interface)

Then visit http://localhost:9001 in your browser. Login with the default credentials `minioadmin / minioadmin` (or your custom credentials if set). The default credentials should be changed immediately in production environments. Use the `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD` environment variables to set custom credentials (minimum 8 characters for password).

## Common MinIO use cases

Run MinIO for development

### Start MinIO with custom credentials

Ensure that no containers are running on the required ports:

```
$ docker run -d --name minio-test -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=myadmin \
    -e MINIO_ROOT_PASSWORD=mypassword123 \
    <your-namespace>/dhi-minio:<tag> \
    server /data --console-address ":9001"

# Test that MinIO is available
$ curl -f http://localhost:9000/minio/health/live

# Try to login to console with new credentials
# Open: http://localhost:9001
# Use: testadmin / testpassword123

# Access console at http://localhost:9001 with credentials: myadmin / mypassword123

# Cleanup
docker stop minio-test && docker rm minio-test
```

### Run MinIO with persistence


First, clean up any existing container:

```
# Create volume
docker volume create minio-data

# Start MinIO with persistent volume
docker run -d --name minio-persist-test \
    -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=myadmin \
    -e MINIO_ROOT_PASSWORD=mypassword123 \
    -v minio-data:/data \
    dockerdevrel/dhi-minio:0.20251015.172955-debian13 \
    server /data --console-address ":9001"

sleep 10

# Configure AWS CLI
export AWS_ACCESS_KEY_ID=myadmin
export AWS_SECRET_ACCESS_KEY=mypassword123

# Create bucket and upload file
aws --endpoint-url=http://localhost:9000 s3 mb s3://test-bucket
echo "Test persistence data" > test-file.txt
aws --endpoint-url=http://localhost:9000 s3 cp test-file.txt s3://test-bucket/

# Verify
aws --endpoint-url=http://localhost:9000 s3 ls s3://test-bucket/
# Expected: test-file.txt

# Stop and remove container
docker stop minio-persist-test && docker rm minio-persist-test

# Start new container with same volume
docker run -d --name minio-persist-test2 \
    -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=myadmin \
    -e MINIO_ROOT_PASSWORD=mypassword123 \
    -v minio-data:/data \
    dockerdevrel/dhi-minio:0.20251015.172955-debian13 \
    server /data --console-address ":9001"

sleep 10

# Check if data persisted
aws --endpoint-url=http://localhost:9000 s3 ls s3://test-bucket/
# Expected: test-file.txt should still be there

# Download and verify content
aws --endpoint-url=http://localhost:9000 s3 cp s3://test-bucket/test-file.txt downloaded.txt
cat downloaded.txt
# Expected: "Test persistence data"

# Cleanup
docker stop minio-persist-test2 && docker rm minio-persist-test2
docker volume rm minio-data
```


## Integration testing with multi-stage Dockerfile

MinIO Docker Hardened Images provide both development and runtime variants. 
The `-dev` variant includes debugging tools useful for setup and validation stages. Use -dev for build/setup stages and the production variant for the final runtime stage.

This example demonstrates deploying MinIO with custom configuration and initialization scripts using MinIO Docker Hardened Images.

- Create project structure

```
# Create project directory
mkdir minio-deployment
cd minio-deployment

# Create configuration directory
mkdir -p config scripts
```

- Add configuration files

Create `config/config.json`:

```
{
  "version": "1",
  "browser": "on",
  "worm": "off"
}
```

Create `scripts/init-buckets.sh`:

```
#!/bin/sh
echo "MinIO initialization script"
echo "Create buckets and configure policies here"
```

Create a Dockerfile in the project directory:

```
# syntax=docker/dockerfile:1
# ============================================================================
# STAGE 1: Setup stage using MinIO DHI dev variant
# ============================================================================
FROM <your-namespace>/dhi-minio:<tag>-dev AS setup

WORKDIR /app

# Copy configuration and scripts
COPY config/ ./config/
COPY scripts/ ./scripts/

# Add build metadata
RUN echo "Built at: $(date)" > ./config/build-info.txt && \
    echo "Architecture: $(uname -m)" >> ./config/build-info.txt && \
    echo "MinIO version: $(minio --version)" >> ./config/build-info.txt

# Verify files (dev variant includes debugging tools)
RUN echo "=== Setup Stage ===" && \
    echo "Configuration files:" && \
    ls -lh ./config/ && \
    echo "Scripts:" && \
    ls -lh ./scripts/ && \
    echo "✓ Configuration validated"

# ============================================================================
# STAGE 2: Runtime stage using MinIO DHI production variant
# ============================================================================
FROM <your-namespace>/dhi-minio:<tag> AS runtime

WORKDIR /app

# Copy validated configuration from setup stage
COPY --from=setup /app/config/ /etc/minio/
COPY --from=setup /app/scripts/ /app/scripts/

# Environment variables
ENV MINIO_ROOT_USER=admin \
    MINIO_ROOT_PASSWORD=password123

# Metadata
LABEL maintainer="your-team@example.com" \
      description="MinIO DHI with custom configuration" \
      setup.image="<your-namespace>/dhi-minio:<tag>-dev" \
      runtime.image="<your-namespace>/dhi-minio:<tag>"

# MinIO ports
EXPOSE 9000 9001

# Start MinIO server
CMD ["server", "/data", "--console-address", ":9001"]
```

- Build and run MinIO

```
# Build the Docker image
docker build -t minio-production .

# Run MinIO with persistent storage
docker run -d \
  --name minio-server \
  -p 9000:9000 \
  -p 9001:9001 \
  -v minio-data:/data \
  minio-production

# Check build information
docker exec minio-server cat /etc/minio/build-info.txt

# Access MinIO Console at http://localhost:9001
# Use credentials: admin / password123
```


## Non-hardened images vs Docker Hardened Images

| Feature | Docker Official MinIO | Docker Hardened MinIO |
|---------|----------------------|----------------------|
| Security | Standard base with common utilities | Hardened base with reduced utilities |
| Shell access | Direct shell access (bash/sh) | Ony -dev variant has sh shell |
| Package manager | Full package managers (apt/apk) | System package managers removed |
| User | Runs as root by default | Only dev variant has root |
| Attack surface | Full system utilities available | Significantly reduced (tested utilities removed) |
| System utilities | Full system toolchain (ls, cat, id, ps, find, rm all present) | Extremely minimal (ls, cat, id, ps, find, rm all removed) |
| Variants | Single variant for all use cases | Two variants - dev and runtime |
| Default credentials | minioadmin / minioadmin | minioadmin / minioadmin (should be changed) |

## Image Variant

Docker Hardened MinIO provides two image variants to support different use cases:

### Runtime variant 

Tags without the `-dev` suffix are optimized for production deployments. These images:

- Are minimal in size: 60.63 MB (amd64) / 56.95 MB (arm64)
- Run as the nonroot user
- Have NO shell at all (maximum security hardening)
- Contain only the minimal set of libraries needed to run MinIO
- Are designed to be used directly or as the FROM image in the final stage of a multi-stage build

### Development variant (-dev tags)

Tags with the `-dev` suffix include debugging and development tools while maintaining the same security posture. These images:

- Are larger: 71.48 MB (amd64) / 67.69 MB (arm64)
- Include a basic shell (sh) and limited debugging tools for troubleshooting
- Run as the root user (for debugging capabilities)
- Include system package managers removed
- Maintain the same security hardening as runtime variants (120 binaries vs 146 in official images)

### Common characteristics

Both variants:

* Have system package managers removed (no apt-get, apk)
* Include only partial system utilities (ls, cat, id, ps present; find, rm, curl, wget absent)
* Use default credentials `minioadmin` / `minioadmin` (must be changed for production use)
* Support both `linux/amd64` and `linux/arm64` architectures
* Are significantly smaller than official MinIO images (~76% size reduction)


## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the
base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the
following table of migration notes.

| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
| :----------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image         | Replace your base images in your Dockerfile with a Docker Hardened Image.                                                                                                                                                                                                                                                    |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a `dev` tag.                                                                                                                                                                                                  |
| Non-root user      | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user.                                                                                                                                                                   |
| Multi-stage build  | Utilize images with a `dev` tag for build stages and non-dev images for runtime. For binary executables, use a `static` image for runtime.                                                                                                                                                                                   |
| TLS certificates   | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates.                                                                                                                                                                                                           |
| Ports              | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. |
| Entry point        | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.                                                                                                                                  |
| No shell           | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage.                                                                                                                                                  |

The following steps outline the general migration process.

1. Find hardened images for your app.

   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.

1. Update the base image in your Dockerfile.

   Update the base image in your application's Dockerfile to the hardened image you found in the previous step. For
   framework images, this is typically going to be an image tagged as `dev` because it has the tools needed to install
   packages and dependencies.

1. For multi-stage Dockerfiles, update the runtime image in your Dockerfile.

   To ensure that your final image is as minimal as possible, you should use a multi-stage build. All stages in your
   Dockerfile should use a hardened image. While intermediary stages will typically use images tagged as `dev`, your
   final runtime stage should use a non-dev image variant.

1. Install additional packages

   Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to
   install additional packages in your Dockerfile. Inspect the image variants to identify which packages are already
   installed.

   Only images tagged as `dev` typically have package managers. You should use a multi-stage Dockerfile to install the
   packages. Install the packages in the build stage that uses a `dev` image. Then, if needed, copy any necessary
   artifacts to the runtime stage that uses a non-dev image.

   For Alpine-based images, you can use `apk` to install packages. For Debian-based images, you can use `apt-get` to
   install packages.

## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for
debugging applications built with Docker Hardened Images is to use
[Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to these containers. Docker Debug provides
a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists
during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot user. Ensure that necessary files and directories are
accessible to the nonroot user. You may need to copy files to different directories or change permissions so your
application running as the nonroot user can access them.

For Grype specifically, ensure that:

- Volume mounts are readable by the nonroot user (UID 65532)
- Configuration files have appropriate permissions
- Output directories are writable by the nonroot user
- Cache directories (`/root/.cache/grype`) are accessible

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to
privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues,
configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on
the host. For example, `docker run -p 80:8080 my-image` will work because the port inside the container is 8080, and
`docker run -p 80:81 my-image` won't work because the port inside the container is 81.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev` images in build stages to run shell
commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers
with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect`
to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.
