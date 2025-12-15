# ClickHouse Metrics Exporter

## Prerequisites

Before you can use any Docker Hardened Image, you must mirror the image 
repository from the catalog to your organization. To mirror the repository, 
select either **Mirror to repository** or 
**View in repository > Mirror to repository**, and then follow the 
on-screen instructions.

## Start a ClickHouse Metrics Exporter instance

The ClickHouse Metrics Exporter collects metrics from a ClickHouse server and exposes them in Prometheus format for monitoring and observability.

Run the following command and replace `<your-namespace>` with your organization's 
namespace and `<tag>` with the image variant you want to run.

```bash
# Pull ClickHouse server image
docker pull dockerdevrel/dhi-clickhouse-server:25

# Create network
docker network create test-net

# Run ClickHouse server
docker run -d \
  --name clickhouse-server \
  --network test-net \
  --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  <your-namespace>/dhi-clickhouse-server:<tag>

# Wait for startup
sleep 15

# Run metrics exporter connected to ClickHouse
docker run -d \
  --name clickhouse-exporter \
  --network test-net \
  -p 9116:9116 \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  <your-namespace>/dhi-clickhouse-metrics-exporter:<tag>

# Check metrics (should show actual ClickHouse metrics)
curl -s http://localhost:9116/metrics | grep clickhouse

# Cleanup
docker rm -f clickhouse-server clickhouse-exporter
docker network rm test-net
```

Verify the exporter is running and collecting metrics:

```bash
curl http://localhost:9116/metrics
```

## Common ClickHouse Metrics Exporter use cases

### Run exporter with Docker network

For better isolation, run both ClickHouse server and metrics exporter on the same Docker network:

```bash
# Create a network
docker network create clickhouse-net

# Run ClickHouse server
docker run -d \
  --name clickhouse-server \
  --network clickhouse-net \
  --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  <your-namespace>/dhi-clickhouse-server:<tag>

# Run metrics exporter
docker run -d \
  --name clickhouse-exporter \
  --network clickhouse-net \
  -p 9116:9116 \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  <your-namespace>/dhi-clickhouse-metrics-exporter:<tag>
```

### Run exporter with persistent configuration

Mount a custom configuration file to specify which metrics to collect:

```bash
cat > scrape-config.yml << EOF
metrics:
  - query: "SELECT version() as version"
    name: clickhouse_version_info
    help: "ClickHouse version information"
    labels:
      - version
  - query: "SELECT count() FROM system.tables"
    name: clickhouse_tables_total
    help: "Total number of tables"
EOF

docker run -d \
  --name clickhouse-exporter \
  -p 9116:9116 \
  -v $(pwd)/scrape-config.yml:/config/scrape-config.yml:ro \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CONFIG_FILE=/config/scrape-config.yml \
  <your-namespace>/dhi-clickhouse-metrics-exporter:<tag>
```

### Integrate with Prometheus

Add the following to your Prometheus configuration to scrape metrics from the exporter:

```yaml
scrape_configs:
  - job_name: 'clickhouse'
    static_configs:
      - targets: ['clickhouse-exporter:9116']
```

### Run exporter with authentication

For secure deployments, configure authentication to protect the metrics endpoint:

```bash
docker run -d \
  --name clickhouse-exporter \
  -p 9116:9116 \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  -e EXPORTER_USER=prometheus \
  -e EXPORTER_PASSWORD=exporter_secret \
  <your-namespace>/dhi-clickhouse-metrics-exporter:<tag>
```

Test the metrics endpoint with authentication:

```bash
curl -u prometheus:exporter_secret http://localhost:9116/metrics
```

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Standard ClickHouse Exporter | Docker Hardened ClickHouse Metrics Exporter |
|---------|------------------------------|---------------------------------------------|
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | No shell in runtime variants |
| Package manager | Package manager available | No package manager in runtime variants |
| User | May run as root | Runs as nonroot user |
| Attack surface | Larger due to additional utilities | Minimal, only essential components |
| Debugging | Traditional shell debugging | Use Docker Debug or Image Mount for troubleshooting |

### Why no shell or package manager?

Docker Hardened Images prioritize security through minimalism:

- Reduced attack surface: Fewer binaries mean fewer potential vulnerabilities
- Immutable infrastructure: Runtime containers shouldn't be modified after deployment
- Compliance ready: Meets strict security requirements for regulated environments

The hardened images intended for runtime don't contain a shell nor any tools for
debugging. Common debugging methods for applications built with Docker
Hardened Images include:

- [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to containers
- Docker's Image Mount feature to mount debugging tools
- Ecosystem-specific debugging approaches

Docker Debug provides a shell, common debugging tools, and lets you
install other tools in an ephemeral, writable layer that only exists during the
debugging session.

For example, you can use Docker Debug:

```bash
docker debug clickhouse-exporter
```

or mount debugging tools with the Image Mount feature:

```bash
docker run --rm -it --pid container:clickhouse-exporter \
  --mount=type=image,source=<your-namespace>/dhi-busybox,destination=/dbg,ro \
  <your-namespace>/dhi-clickhouse-metrics-exporter:<tag> /dbg/bin/sh
```

## Image variants

Docker Hardened Images come in different variants depending on their intended use.

Runtime variants are designed to run your application in production. 
These images are intended to be used either directly or as the `FROM` image in 
the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Do not include a shell or a package manager
- Contain only the minimal set of libraries needed to run the app

Build-time variants typically include `dev` in the variant name and are 
intended for use in the first stage of a multi-stage Dockerfile. These images 
typically:

- Run as the root user
- Include a shell and package manager
- Are used to build or compile applications

The ClickHouse Metrics Exporter Docker Hardened Image is available as runtime variants only. There are no `dev` variants for this image.

### Available tags

The following tags are available:

- `0` or `0-debian13` - Latest version 0.x series with Debian 13 base
- `0.25` or `0.25-debian13` - Version 0.25.x with Debian 13 base
- `0.25.6` or `0.25.6-debian13` - Specific version 0.25.6 with Debian 13 base

All variants support both `linux/amd64` and `linux/arm64` architectures.

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your 
Dockerfile. At minimum, you must update the base image in your existing 
Dockerfile to a Docker Hardened Image. This and a few other common changes are 
listed in the following table of migration notes:

| Item | Migration note |
|------|----------------|
| Base image | Replace your base images in your Dockerfile with a Docker Hardened Image. |
| Non-root user | By default, images run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| Ports | Hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. The default exporter port 9116 works without issues. |
| Entry point | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| Configuration | Configuration via environment variables is the recommended approach. Mount configuration files as read-only when needed. |

The following steps outline the general migration process:

1. **Find hardened images for your app.**
    
    A hardened image may have several variants. Inspect the image tags and 
    find the image variant that meets your needs. ClickHouse Metrics Exporter images are available in version 0.25.6 with Debian 13 base.
    
2. **Update the base image in your Dockerfile.**
    
    Update the base image in your application's Dockerfile to the hardened 
    image you found in the previous step.
    
3. **Verify permissions**
    
    Since the image runs as nonroot user, ensure that configuration files and mounted volumes are accessible to the nonroot user. You may need to adjust file permissions or ownership.

## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools 
for debugging. The recommended method for debugging applications built with 
Docker Hardened Images is to use 
[Docker Debug](https://docs.docker.com/engine/reference/commandline/debug/) to 
attach to these containers. Docker Debug provides a shell, common debugging 
tools, and lets you install other tools in an ephemeral, writable layer that 
only exists during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot user. 
Ensure that necessary files and directories are accessible to the nonroot user. 
You may need to copy files to different directories or change permissions so 
your application running as the nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, 
applications in these images can't bind to privileged ports (below 1024) when 
running in Kubernetes or in Docker Engine versions older than 20.10. The default exporter port (9116) is above 1024 and works without issues.

### No shell

By default, image variants intended for runtime don't contain a shell. Use 
dev images in build stages to run shell commands and then copy any necessary 
artifacts into the runtime stage. In addition, use Docker Debug to debug 
containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as 
Docker Official Images. Use `docker inspect` to inspect entry points for 
Docker Hardened Images and update your Dockerfile if necessary.

