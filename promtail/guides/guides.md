## How to use this image

Before you can use any Docker Hardened Image, you must mirror the image repository from the catalog to your organization. To mirror the repository, select either **Mirror to repository** or **View in repository** > **Mirror to repository**, and then follow the on-screen instructions.

### Start a Promtail instance

To start an Promtail instance, run the following command. Replace `<your-namespace>` with your organization's namespace
and `<tag>` with the image variant you want to run.

Promtail is an agent which ships the contents of local logs to a Grafana Loki instance. Promtail requires configuration to function. The following command creates a configuration file that tells Promtail to collect all .log files from `/var/log`, track their read positions, and push them to Loki at `http://loki:3100` with the label `job="varlogs".

```
# Create directory structure
mkdir -p promtail/config

# Create basic Promtail configuration
cat > promtail/config/promtail.yml <<'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*.log
EOF
```


#### Run Promtail with the configuration

The following commands creates a Docker network named `logging-net`, then starts Loki (port `3100`) and Promtail (port `9080`) containers on that network, with Promtail configured to read `/var/log` files and send them to Loki.

```
# Create logging network (ignore if exists)
docker network create logging-net 2>/dev/null || true

# Start Loki (DHI)
docker run -d --name loki \
  --network logging-net \
  -p 3100:3100 \
  dockerdevrel/dhi-loki:3 \
  -config.file=/etc/loki/local-config.yaml

# Start Promtail
docker run -d --name promtail \
  --network logging-net \
  -p 9080:9080 \
  -v $PWD/promtail/config/promtail.yml:/etc/promtail/config.yml:ro \
  -v /var/log:/var/log:ro \
  dockerdevrel/dhi-promtail:3.5.8 \
  -config.file=/etc/promtail/config.yml
```


#### Verify the setup

By now, Promtail should be accessible via `http://localhost:9080/targets`. 
This page shows all the log files being monitored and their current status.

Let's verify they are up and healthy:


```
cat > verify-promtail-loki.sh << 'EOF'
#!/bin/bash

# Promtail and Loki Setup Verification Script
# This script verifies that Promtail and Loki are running correctly

set -e  # Exit on error

echo "=== Starting Verification Process ==="
echo ""

# Wait for services to start
echo "Waiting for services to initialize..."
sleep 15

# Check containers are running
echo "Checking if containers are running..."
docker ps | grep -E "promtail|loki"
echo ""

# Check Promtail logs
echo "Checking Promtail logs (last 10 lines)..."
docker logs promtail | tail -n 10
echo ""

# Check Promtail metrics and log collection
echo "Checking Promtail metrics..."
echo "Active targets:"
curl -s http://localhost:9080/metrics | grep promtail_targets_active_total
echo ""
echo "Sent entries:"
curl -s http://localhost:9080/metrics | grep promtail_sent_entries_total
echo ""

# Wait for Loki to be fully ready
echo "Waiting for Loki to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:3100/ready 2>/dev/null | grep -q "ready"; then
    echo "Loki is ready!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done
echo ""

# Check available labels
echo "Checking available labels in Loki..."
curl -s http://localhost:3100/loki/api/v1/labels | jq
echo ""

# Query logs from Loki
echo "Querying logs from Loki..."
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'limit=5' | jq '.data.result[0].values'

echo ""
echo "=== Setup Complete ==="
echo "Promtail metrics: http://localhost:9080/metrics"
echo "Loki API: http://localhost:3100"
echo ""
EOF

# Make the script executable
chmod +x verify-promtail-loki.sh

# Run the verification
./verify-promtail-loki.sh
```

Note on ports: This example uses non-privileged port 9080 which works reliably with the nonroot user (UID 65532) across all environments.

## Common Promtail use cases

### Multiple log sources with labels

Configure Promtail to collect logs from multiple sources with custom labels for better organization. The following commands demonstrates multi-source logs collections where:

- 3 different apps (webapp, api, worker) write logs to separate directories
- Promtail collects all using a single configuration with multiple scrape_configs
- Each source gets unique labels (job="webapp", job="api", job="worker")
- You can filter logs by label in Loki queries

```
# Step 1: Clean up
docker rm -f promtail loki 2>/dev/null || true

# Step 2: Create application directories
mkdir -p app-logs/webapp
mkdir -p app-logs/api
mkdir -p app-logs/worker

# Step 3: Create configuration for multiple sources
cat > promtail/config/promtail.yml <<'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: webapp
    static_configs:
      - targets:
          - localhost
        labels:
          job: webapp
          env: production
          __path__: /logs/webapp/*.log

  - job_name: api
    static_configs:
      - targets:
          - localhost
        labels:
          job: api
          env: production
          __path__: /logs/api/*.log

  - job_name: worker
    static_configs:
      - targets:
          - localhost
        labels:
          job: worker
          env: production
          __path__: /logs/worker/*.log
EOF

# Step 4: Start Loki (DHI)
docker run -d --name loki \
  --network logging-net \
  -p 3100:3100 \
  dockerdevrel/dhi-loki:3 \
  -config.file=/etc/loki/local-config.yaml

# Step 5: Start Promtail with multiple log directories
docker run -d --name promtail \
  --network logging-net \
  -p 9080:9080 \
  -v $PWD/promtail/config/promtail.yml:/etc/promtail/config.yml:ro \
  -v $PWD/app-logs:/logs:ro \
  dockerdevrel/dhi-promtail:3.5.8 \
  -config.file=/etc/promtail/config.yml

# Step 6: Generate test logs
echo "$(date) - User login successful" >> app-logs/webapp/access.log
echo "$(date) - API request processed" >> app-logs/api/requests.log
echo "$(date) - Background job completed" >> app-logs/worker/jobs.log

# Step 7: Wait and verify
sleep 20
echo "=== Available jobs in Loki ==="
curl -s http://localhost:3100/loki/api/v1/label/job/values | jq

echo ""
echo "=== Query logs by job ==="
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="webapp"}' \
  --data-urlencode 'limit=5' | jq '.data.result[0].values'
```


## Multi-stage Dockerfile integration

Since Promtail DHI images do NOT provide dev variants with shell or package managers, multi-stage builds with DHI images are limited to copying static files and configurations.


```
cat > Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
# Build stage - Use a DHI base image for configuration preparation
FROM dockerdevrel/dhi-busybox:1.37.0 AS builder

# Copy configuration files
COPY config/promtail.yml /app/config/promtail.yml

# Ensure proper ownership (busybox has basic commands)
RUN chown -R 65532:65532 /app/config

# Runtime stage - Use Docker Hardened Promtail
FROM dockerdevrel/dhi-promtail:3.5.8 AS runtime

# Copy configuration from builder
COPY --from=builder --chown=65532:65532 /app/config/promtail.yml /etc/promtail/config.yml

EXPOSE 9080

# Override entrypoint to use custom config location
ENTRYPOINT ["/usr/bin/promtail"]
CMD ["-config.file=/etc/promtail/config.yml"]
EOF

# Build
docker build -t ajeetraina/promtail .
```

Important: Docker Hardened Images run as a nonroot user (UID 65532) for security. This user cannot access the Docker daemon socket (/var/run/docker.sock) without additional permissions, which would compromise the security model.
For collecting Docker container logs with Promtail DHI, consider these alternatives:

- File-based collection: Mount container log directories and collect from files
- Centralized logging driver: Use Docker's logging drivers to write to files that Promtail can read
- Sidecar pattern: Run Promtail as a sidecar container with shared log volumes

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Grafana Promtail | Docker Hardened Promtail |
|---------|------------------|--------------------------|
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | No shell in runtime variants |
| Package manager | apk available | No package manager in runtime variants |
| User | Runs as root by default | Runs as nonroot user (UID 65532) |
| Attack surface | Larger due to additional utilities | Minimal, only essential components |
| Debugging | Traditional shell debugging | Use Docker Debug or Image Mount for troubleshooting |


## Image variants

Docker Hardened Images come in different variants depending on their intended use.

- Runtime variants are designed to run your application in production. These images are intended to be used either
  directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

  - Run as the nonroot user
  - Do not include a shell or a package manager
  - Contain only the minimal set of libraries needed to run the app

- Build-time variants typically include `dev` in the variant name and are intended for use in the first stage of a
  multi-stage Dockerfile. These images typically:

  - Run as the root user
  - Include a shell and package manager
  - Are used to build or compile applications

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
| Ports              | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can’t bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. |
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
