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

Then visit http://localhost:9001 in your browser. Login with the default credentials `minioadmin / minioadmin` (or your custom credentials if set)

## Common MinIO use cases

Run MinIO for development

Start MinIO with custom credentials:

```
$ docker run -d -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=myadmin \
    -e MINIO_ROOT_PASSWORD=mypassword123 \
    <your-namespace>/dhi-minio:<tag> \
    server /data --console-address ":9001"

# Test that MinIO is available
$ curl -f http://localhost:9000/minio/health/live

# Access console at http://localhost:9001 with credentials: myadmin / mypassword123
```

## Run MinIO with persistence

This example demonstrates how to enable data persistence in MinIO, which means your object storage data will survive container restarts instead of being lost each time. The setup requires creating a Docker volume (minio-data) and mounting it to MinIO's data directory (/data).

Enable data persistence across container restarts:

```
# Create a volume
$ docker volume create minio-data

$ docker run -d --name minio-persist-test \
    -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=myadmin \
    -e MINIO_ROOT_PASSWORD=mypassword123 \
    -v minio-data:/data \
    <your-namespace>/dhi-minio:<tag> \
    server /data --console-address ":9001"

# Verify MinIO is running
$ curl -f http://localhost:9000/minio/health/live

# Create test data using MinIO client (mc) or AWS CLI
aws --endpoint-url=http://localhost:9000 s3 mb s3://test-bucket
aws --endpoint-url=http://localhost:9000 s3 cp /etc/hosts s3://test-bucket/test-file.txt

# Verify data exists
aws --endpoint-url=http://localhost:9000 s3 ls
aws --endpoint-url=http://localhost:9000 s3 ls s3://test-bucket

# Stop the container
$ docker stop minio-persist-test
$ docker rm minio-persist-test

# Start new container with same volume
$ docker run -d --name minio-persist-test2 \
    -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=myadmin \
    -e MINIO_ROOT_PASSWORD=mypassword123 \
    -v minio-data:/data \
    <your-namespace>/dhi-minio:<tag> \
    server /data --console-address ":9001"

# Verify data persisted
echo "Data after restart:"
aws --endpoint-url=http://localhost:9000 s3 ls
aws --endpoint-url=http://localhost:9000 s3 ls s3://test-bucket
```
Note: When using AWS CLI with MinIO, set your credentials as environment variables:

```
export AWS_ACCESS_KEY_ID=myadmin
export AWS_SECRET_ACCESS_KEY=mypassword123
```

## Integration testing with multi-stage Dockerfile

Important: MinIO Docker Hardened Images are runtime-only variants. MinIO DHI does not provide separate dev variants.

Here's a complete example for integration testing:

```
# syntax=docker/dockerfile:1
# Development stage - Use standard MinIO for testing setup
FROM minio/minio AS test-setup

WORKDIR /app

# Install testing tools and dependencies (standard image has package managers)
RUN apt-get update && apt-get install -y curl jq awscli

# Copy test scripts and configuration
COPY test-scripts/ ./test-scripts/
COPY minio-config/ ./config/

# Runtime stage - MinIO DHI for production deployment
FROM <your-namespace>/dhi-minio:<tag> AS runtime

WORKDIR /app
COPY --from=test-setup /app/config/ /etc/minio/

EXPOSE 9000 9001
# Use default MinIO entrypoint
```

## Non-hardened images vs Docker Hardened Images

| Feature | Docker Official MinIO | Docker Hardened MinIO |
|---------|----------------------|----------------------|
| Security | Standard base with common utilities | Hardened base with reduced utilities |
| Shell access | Direct shell access (bash/sh) | Basic shell access (sh) |
| Package manager | Full package managers (apt/apk) | System package managers removed |
| User | Runs as root by default | Runs as nonroot user |
| Attack surface | Full system utilities available | Significantly reduced (tested utilities removed) |
| System utilities | Full system toolchain (ls, cat, id, ps, find, rm all present) | Extremely minimal (ls, cat, id, ps, find, rm all removed) |
| Variants | Single variant for all use cases | Runtime-only (no dev variants) |
| Default credentials | minioadmin / minioadmin | minioadmin / minioadmin (should be changed) |

## Image variants

Docker Hardened MinIO images are runtime-only variants. Unlike other DHI products (such as Maven), MinIO DHI does not provide separate dev variants with additional development tools.

Runtime variants are designed to run MinIO in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Include basic shell with system package managers removed
- Contain only the minimal set of libraries needed to run MinIO
- Support both regular and `-dev` tags (dev tags include debugging tools but maintain the same security posture)
- Use default credentials `minioadmin` / `minioadmin` (must be changed for production)


## Image variants

Docker Hardened MinIO images are runtime-only variants. Unlike other DHI products (such as Maven), MinIO DHI does not provide separate dev variants with additional development tools.

Runtime variants are designed to run MinIO in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Include basic shell with system package managers removed
- Contain only the minimal set of libraries needed to run MinIO
- Support both regular and `-dev` tags (dev tags include debugging tools but maintain the same security posture)
- Use default credentials `minioadmin` / `minioadmin` (must be changed for production)

## Migrate to a Docker Hardened Image

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

### Grype-specific troubleshooting

#### Database connectivity issues

If Grype fails to download vulnerability databases, ensure network connectivity:

```bash
# Test database update separately
docker run --rm <your-namespace>/dhi-grype:<tag> db update

# Check database status
docker run --rm <your-namespace>/dhi-grype:<tag> db status
```

#### Large image scanning performance

For very large images, consider increasing memory limits:

```bash
# Increase memory for large scans
docker run --rm --memory=4g <your-namespace>/dhi-grype:<tag> huge-image:latest
```

#### False positive management

Use ignore rules and VEX documents to manage false positives systematically:

```bash
# Test ignore rules configuration
docker run --rm -v $(pwd)/.grype.yaml:/root/.grype.yaml <your-namespace>/dhi-grype:<tag> ubuntu:latest

# Validate VEX document application
docker run --rm -v $(pwd)/filter.vex.json:/vex.json <your-namespace>/dhi-grype:<tag> ubuntu:latest --vex /vex.json
```

#### Template formatting issues

For custom templates, validate template syntax:

```bash
# Test custom template with simple data
echo '{"matches": []}' | docker run --rm -i -v $(pwd)/template.tmpl:/template <your-namespace>/dhi-grype:<tag> -o template -t /template
```
