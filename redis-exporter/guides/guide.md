# Redis Exporter Docker Hardened Image (DHI) Guide

## How to use this image

Redis Exporter is a Prometheus exporter for Redis metrics. It exposes metrics from Redis instances via HTTP endpoints that can be scraped by Prometheus or other monitoring systems.

### Available tags

The `dockerdevrel/dhi-redis-exporter` image provides Debian-based variants only:

- **Standard Debian-based**: `1.80.1-debian13`, `1.80-debian13`, `1-debian13`, `1.80.1`, `1.80`, `1`
  - **Uncompressed**: ~24MB, **Compressed**: ~7.37MB
  
- **FIPS Debian-based**: `1.80.1-debian13-fips`, `1.80-debian13-fips`, `1-debian13-fips`, `1.80.1-fips`, `1.80-fips`, `1-fips`
  - **Uncompressed**: ~60MB, **Compressed**: ~19.16MB

All variants support both `linux/amd64` and `linux/arm64` architectures.

### Start a redis-exporter DHI container

To run a redis-exporter DHI container:

```bash
# Basic usage - single Redis instance (requires Redis to be accessible)
$ docker run -d \
  --name redis-exporter \
  -p 9121:9121 \
  dockerdevrel/dhi-redis-exporter:1.80.1 \
  --redis.addr=redis://redis-server:6379

# Multi-target mode - no specific Redis instance (useful for testing)
$ docker run -d \
  --name redis-exporter-multi \
  -p 9121:9121 \
  dockerdevrel/dhi-redis-exporter:1.80.1 \
  --redis.addr=

# Using FIPS variant for compliance requirements
$ docker run -d \
  --name redis-exporter-fips \
  -p 9121:9121 \
  dockerdevrel/dhi-redis-exporter:1.80.1-fips \
  --redis.addr=redis://redis-server:6379
```

**Note**: If Redis is not accessible at the specified address, the exporter will still start and expose metrics, but `redis_up` will be 0 and connection errors will be visible in the metrics output. The exporter will continue attempting to connect.

### Environment variables

Redis Exporter can be configured using environment variables as an alternative to command-line flags:

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `REDIS_ADDR` | Redis instance address | localhost:6379 | redis://redis:6379 |
| `REDIS_USER` | Redis ACL username | - | myuser |
| `REDIS_PASSWORD` | Redis password | - | secret123 |
| `REDIS_EXPORTER_WEB_LISTEN_ADDRESS` | Address to listen on for web interface and telemetry | 0.0.0.0:9121 | 0.0.0.0:8080 |
| `REDIS_EXPORTER_WEB_TELEMETRY_PATH` | Path under which to expose metrics | /metrics | /custom-metrics |
| `REDIS_EXPORTER_NAMESPACE` | Namespace for metrics | redis | custom_redis |
| `REDIS_EXPORTER_LOG_FORMAT` | Log format (txt or json) | txt | json |
| `REDIS_EXPORTER_DEBUG` | Enable debug output | false | true |

Example with environment variables:

```bash
$ docker run -d \
  --name redis-exporter \
  -p 9121:9121 \
  -e REDIS_ADDR=redis://redis-server:6379 \
  -e REDIS_PASSWORD=mypassword \
  -e REDIS_EXPORTER_LOG_FORMAT=json \
  dockerdevrel/dhi-redis-exporter:1.80.1
```

### Test the redis-exporter DHI instance

Verify redis-exporter is working correctly:

```bash
# Check health endpoint (should return "ok")
$ curl http://localhost:9121/health

# View metrics (will show exporter metrics even without Redis connection)
$ curl http://localhost:9121/metrics

# Verify version and DHI metadata
$ docker inspect dockerdevrel/dhi-redis-exporter:1.80.1 --format='{{.Config.Labels.com.docker.dhi.version}}'
```

**Note**: If you start the exporter without an actual Redis instance available, you'll see `redis_up 0` and a connection error in the metrics. This is expected behavior - the exporter itself is working correctly and will connect once Redis is available.

### Quick test with Redis

To test with an actual Redis instance, use Docker Compose:

```yaml
# quick-test-compose.yml
version: '3.8'
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
  
  redis-exporter:
    image: dockerdevrel/dhi-redis-exporter:1.80.1
    ports:
      - "9121:9121"
    command: --redis.addr=redis://redis:6379
    depends_on:
      - redis
```

```bash
# Start the test stack
$ docker-compose -f quick-test-compose.yml up -d

# Verify Redis connection is successful (redis_up should be 1)
$ curl http://localhost:9121/metrics | grep redis_up

# Clean up
$ docker-compose -f quick-test-compose.yml down
```

## Common redis-exporter DHI use cases

### Single Redis instance monitoring

Monitor a single Redis instance with default settings:

```bash
$ docker run -d \
  --name redis-exporter \
  -p 9121:9121 \
  dockerdevrel/dhi-redis-exporter:1.80.1 \
  --redis.addr=redis://redis-server:6379
```

Access metrics at `http://localhost:9121/metrics` for Prometheus scraping.

### Environment variable configuration

Configure using environment variables instead of command flags:

```bash
$ docker run -d \
  --name redis-exporter \
  -p 9121:9121 \
  -e REDIS_ADDR=redis://redis-server:6379 \
  -e REDIS_EXPORTER_WEB_LISTEN_ADDRESS=0.0.0.0:9121 \
  -e REDIS_EXPORTER_WEB_TELEMETRY_PATH=/metrics \
  dockerdevrel/dhi-redis-exporter:1.80.1
```

### Multi-target monitoring

Run in multi-target mode to scrape multiple Redis instances via the `/scrape` endpoint:

```bash
# Start exporter with empty redis.addr for multi-target mode
$ docker run -d \
  --name redis-exporter-multi \
  -p 9121:9121 \
  dockerdevrel/dhi-redis-exporter:1.80.1 \
  --redis.addr=
```

Then scrape different Redis instances dynamically:

```bash
# Scrape Redis instance 1
$ curl http://localhost:9121/scrape?target=redis://redis-server-1:6379

# Scrape Redis instance 2
$ curl http://localhost:9121/scrape?target=redis://redis-server-2:6380
```

### Custom metrics configuration

Expose metrics on custom port/path and monitor specific keys:

```bash
$ docker run -d \
  --name redis-exporter-custom \
  -p 8080:8080 \
  dockerdevrel/dhi-redis-exporter:1.80.1 \
  --redis.addr=redis://redis-server:6379 \
  --web.listen-address=0.0.0.0:8080 \
  --web.telemetry-path=/custom-metrics \
  --namespace=custom_redis \
  --include-system-metrics \
  --check-single-keys=db0=user:count,db0=queue:tasks
```

### Docker Compose deployment

Complete monitoring stack with Redis and Redis Exporter:

```yaml
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: redis-server
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data

  redis-exporter:
    image: dockerdevrel/dhi-redis-exporter:1.80.1
    container_name: redis-exporter
    ports:
      - "9121:9121"
    command:
      - --redis.addr=redis://redis:6379
      - --include-system-metrics
    depends_on:
      - redis
    restart: unless-stopped

volumes:
  redis-data:
```

Start the stack:

```bash
$ docker-compose up -d

# Verify metrics are being collected
$ curl http://localhost:9121/metrics | grep redis_
```

### FIPS-compliant monitoring

For environments requiring FIPS 140 validated cryptography:

```bash
$ docker run -d \
  --name redis-exporter-fips \
  -p 9121:9121 \
  dockerdevrel/dhi-redis-exporter:1.80.1-fips \
  --redis.addr=redis://redis-server:6379
```

**Note**: FIPS variants disable non-compliant cryptographic operations like MD5.

### Integration with Prometheus

Configure Prometheus to scrape Redis Exporter metrics:

**prometheus.yml**:
```yaml
scrape_configs:
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
```

**docker-compose.yml**:
```yaml
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: redis-server

  redis-exporter:
    image: dockerdevrel/dhi-redis-exporter:1.80.1
    container_name: redis-exporter
    command: --redis.addr=redis://redis:6379
    depends_on:
      - redis

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
    depends_on:
      - redis-exporter
```

### Multi-stage Dockerfile integration

Build a custom monitoring solution with Redis Exporter:

```dockerfile
# syntax=docker/dockerfile:1
# Configuration stage
FROM alpine:latest AS config-builder

WORKDIR /config

# Create custom exporter configuration
RUN echo '#!/bin/sh' > start-exporter.sh && \
    echo 'exec /redis_exporter "$@"' >> start-exporter.sh && \
    chmod +x start-exporter.sh

# Create Prometheus scrape configuration
RUN cat > redis-targets.yml <<EOF
- targets:
  - redis://redis-primary:6379
  - redis://redis-replica-1:6379
  - redis://redis-replica-2:6379
  labels:
    env: production
EOF

# Runtime stage - DHI for production
FROM dockerdevrel/dhi-redis-exporter:1.80.1

WORKDIR /app

# Copy configuration from builder stage
COPY --from=config-builder /config/redis-targets.yml /app/redis-targets.yml

# Default command with custom settings
CMD ["--redis.addr=redis://redis:6379", "--include-system-metrics", "--namespace=production"]
```

Build and run:

```bash
# Build the image
$ docker build -t my-redis-exporter .

# Run with custom configuration
$ docker run -d \
  --name my-redis-exporter \
  -p 9121:9121 \
  my-redis-exporter
```

### Monitoring Redis Cluster

Monitor a Redis Cluster with authentication:

```bash
$ docker run -d \
  --name redis-exporter-cluster \
  -p 9121:9121 \
  dockerdevrel/dhi-redis-exporter:1.80.1 \
  --redis.addr=redis://redis-cluster:6379 \
  --redis.password=your-secure-password \
  --is-cluster \
  --check-keys=* \
  --check-single-keys=db0=user:*,db0=session:*
```

### Choosing between variants

**Standard Debian variants** (`1.80.1-debian13`):
- **Pros**: Smaller size (7.37MB compressed), standard cryptography, sufficient for most use cases
- **Cons**: Not FIPS-compliant
- **Use when**: Standard monitoring needs, no regulatory requirements for FIPS

**FIPS Debian variants** (`1.80.1-debian13-fips`):
- **Pros**: FIPS 140 validated cryptography, regulatory compliance
- **Cons**: Larger size (19.16MB compressed), restricts some cryptographic operations
- **Use when**: Government/regulated environments, compliance requirements mandate FIPS

**Both variants**: Hardened with no shell access - use `docker debug` if debugging is needed.

## Non-hardened images vs Docker Hardened Images

| Feature | Standard Redis Exporter Images | Docker Hardened Redis Exporter |
|---------|-------------------------------|--------------------------------|
| **Security** | Standard base image | Hardened base with reduced attack surface |
| **Shell access** | Shell available | No shell access (exporter-only) |
| **Package manager** | Package managers available | Package managers removed |
| **User** | May run as root | Runs as nonroot user |
| **System utilities** | Full system utilities | Minimal utilities (no debugging tools) |
| **FIPS compliance** | Not available | FIPS variants available |
| **Image size** | Varies | Optimized and minimal |
| **Debugging** | Standard tools available | Requires `docker debug` |

## Image variants

Docker Hardened Images come in different variants depending on their intended use. Image variants are identified by their tag.

- Runtime variants are designed to run your application in production. These images are intended to be used either directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

  - Run as a nonroot user
  - Do not include a shell or a package manager
  - Contain only the minimal set of libraries needed to run the app

- Build-time variants typically include `dev` in the tag name and are intended for use in the first stage of a multi-stage Dockerfile. These images typically:

  - Run as the root user
  - Include a shell and package manager
  - Are used to build or compile applications

- FIPS variants include `fips` in the variant name and tag. They come in both runtime and build-time variants. These variants use cryptographic modules that have been validated under FIPS 140, a U.S. government standard for secure cryptographic operations. For example, usage of MD5 fails in FIPS variants.

To view the image variants and get more information about them, select the **Tags** tab for this repository, and then select a tag.

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the following table of migration notes.

| Item               | Migration note                                                                                                                                                                                                                                                                                                                               |
| :----------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image         | Replace your base images in your Dockerfile with a Docker Hardened Image.                                                                                                                                                                                                                                                                    |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a `dev` tag.                                                                                                                                                                                                                  |
| Nonroot user       | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user.                                                                                                                                                                            |
| Multi-stage build  | Utilize images with a `dev` tag for build stages and non-dev images for runtime. For binary executables, use a `static` image for runtime.                                                                                                                                                                                                   |
| TLS certificates   | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates.                                                                                                                                                                                                                           |
| Ports              | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. |
| Entry point        | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.                                                                                                                                                  |
| No shell           | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage.                                                                                                                                                                  |

The following steps outline the general migration process.

1. Find hardened images for your app.

   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.

1. Update the base image in your Dockerfile.

   Update the base image in your application's Dockerfile to the hardened image you found in the previous step. For framework images, this is typically going to be an image tagged as `dev` because it has the tools needed to install packages and dependencies.

1. For multi-stage Dockerfiles, update the runtime image in your Dockerfile.

   To ensure that your final image is as minimal as possible, you should use a multi-stage build. All stages in your Dockerfile should use a hardened image. While intermediary stages will typically use images tagged as `dev`, your final runtime stage should use a non-dev image variant.

1. Install additional packages

   Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to install additional packages in your Dockerfile. Inspect the image variants to identify which packages are already installed.

   Only images tagged as `dev` typically have package managers. You should use a multi-stage Dockerfile to install the packages. Install the packages in the build stage that uses a `dev` image. Then, if needed, copy any necessary artifacts to the runtime stage that uses a non-dev image.

   For Alpine-based images, you can use `apk` to install packages. For Debian-based images, you can use `apt-get` to install packages.

## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for debugging applications built with Docker Hardened Images is to use [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so your application running as the nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on the host. For example, `docker run -p 80:8080 my-image` will work because the port inside the container is 8080, and `docker run -p 80:81 my-image` won't work because the port inside the container is 81.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev` images in build stages to run shell commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.
