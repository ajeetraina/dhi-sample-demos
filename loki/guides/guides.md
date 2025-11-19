# Docker Hardened Loki

## Prerequisites

Before you can use any Docker Hardened Image, you must mirror the image repository from the catalog to your organization. To mirror the repository, select either **Mirror to repository** or **View in repository > Mirror to repository**, and then follow the on-screen instructions.

## Start a Loki instance

Run the following command and replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.
```bash
docker run -d -p 3100:3100 <your-namespace>/dhi-loki:<tag>
```

For example, to run Loki 3.5.8:
```bash
docker run -d -p 3100:3100 <your-namespace>/dhi-loki:3.5.8
```

## Common Loki use cases

### Log aggregation with Promtail

Loki works seamlessly with Promtail for collecting and shipping logs. Here's how to set up a basic log collection pipeline:
```bash
# Start Loki
docker run -d --name loki -p 3100:3100 <your-namespace>/dhi-loki:3.5.8

# Create Promtail configuration
cat > promtail-config.yaml <<EOF
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
          __path__: /var/log/*log
EOF

# Start Promtail (using Docker Official Image as example)
docker run -d --name promtail \
  --link loki \
  -v $(pwd)/promtail-config.yaml:/etc/promtail/config.yml \
  -v /var/log:/var/log \
  grafana/promtail:latest -config.file=/etc/promtail/config.yml
```

### Integration with Grafana

Loki integrates with Grafana for log visualization and querying:
```bash
# Start Loki
docker run -d --name loki -p 3100:3100 <your-namespace>/dhi-loki:3.5.8

# Start Grafana (using Docker Official Image as example)
docker run -d --name grafana -p 3000:3000 --link loki grafana/grafana:latest
```

Then configure Loki as a data source in Grafana:
- URL: `http://loki:3100`
- Type: Loki

### Custom configuration

Run Loki with a custom configuration file:
```bash
# Create your Loki configuration
cat > loki-config.yaml <<EOF
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks
EOF

# Run with custom configuration
docker run -d --name loki \
  -p 3100:3100 \
  -v $(pwd)/loki-config.yaml:/etc/loki/config.yaml \
  -v loki-data:/loki \
  <your-namespace>/dhi-loki:3.5.8 \
  -config.file=/etc/loki/config.yaml
```

### Query logs via API

Query logs directly using Loki's HTTP API:
```bash
# Query logs with label filter
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'limit=10'

# Get labels
curl -s "http://localhost:3100/loki/api/v1/labels"
```

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Docker Official Loki | Docker Hardened Loki |
|---------|------------------------------|------------------------------|
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | No shell in runtime variants |
| Package manager | apt/apk available | No package manager in runtime variants |
| User | Runs as root by default | Runs as nonroot user |
| Attack surface | Larger due to additional utilities | Minimal, only essential components |
| Debugging | Traditional shell debugging | Use Docker Debug or Image Mount for troubleshooting |

### Why no shell or package manager?

Docker Hardened Images prioritize security through minimalism:

- **Reduced attack surface**: Fewer binaries mean fewer potential vulnerabilities
- **Immutable infrastructure**: Runtime containers shouldn't be modified after deployment
- **Compliance ready**: Meets strict security requirements for regulated environments

The hardened images intended for runtime don't contain a shell nor any tools for debugging. Common debugging methods for applications built with Docker Hardened Images include:

- [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to containers
- Docker's Image Mount feature to mount debugging tools
- Ecosystem-specific debugging approaches

Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

For example, you can use Docker Debug:
```bash
docker debug <container-name>
```

or mount debugging tools with the Image Mount feature:
```bash
docker run --rm -it --pid container:loki \
  --mount=type=image,source=<your-namespace>/dhi-busybox,destination=/dbg,ro \
  <your-namespace>/dhi-loki:3.5.8 /dbg/bin/sh
```

## Image variants

Docker Hardened Images come in different variants depending on their intended use.

**Runtime variants** are designed to run your application in production. These images are intended to be used either directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Do not include a shell or a package manager
- Contain only the minimal set of libraries needed to run the app

**Build-time variants** typically include `dev` in the variant name and are intended for use in the first stage of a multi-stage Dockerfile. These images typically:

- Run as the root user
- Include a shell and package manager
- Are used to build or compile applications

### FIPS variants

FIPS variants include `fips` in the variant name and tag. They come in both runtime and build-time variants. These variants use cryptographic modules that have been validated under FIPS 140, a U.S. government standard for secure cryptographic operations.

Available FIPS tags for Loki include:
- `2.9.17-fips`, `2.9.17-debian13-fips`
- `3.4.6-fips`, `3.4.6-debian13-fips`
- `3.5.8-fips`, `3.5.8-debian13-fips`

**FIPS Runtime Requirements:**
- FIPS mode enforces strict cryptographic operations
- MD5 and other non-compliant algorithms will fail
- Ensure your Loki configuration doesn't use deprecated hash algorithms

**Verify FIPS mode:**
```bash
docker run --rm <your-namespace>/dhi-loki:3.5.8-fips \
  cat /proc/sys/crypto/fips_enabled
# Should output: 1
```

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the following table of migration notes:

| Item | Migration note |
|------|----------------|
| Base image | Replace your base images in your Dockerfile with a Docker Hardened Image. |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a dev tag. |
| Non-root user | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. |
| Multi-stage build | Utilize images with a dev tag for build stages and non-dev images for runtime. For binary executables, use a static image for runtime. |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| Ports | Non-dev hardened images run as a nonroot user by default. Loki's default port 3100 is above 1024, so it works without issues. |
| Entry point | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| No shell | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage. |

The following steps outline the general migration process:

1. **Find hardened images for your app.**
    
    A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs. For Loki, current versions include 2.9.17, 3.4.6, and 3.5.8.
    
2. **Update the base image in your Dockerfile.**
    
    Update the base image in your application's Dockerfile to the hardened image you found in the previous step.
```dockerfile
    # Before
    FROM grafana/loki:2.9.0
    
    # After
    FROM <your-namespace>/dhi-loki:2.9.17
```
    
3. **For multi-stage Dockerfiles, update the runtime image in your Dockerfile.**
    
    To ensure that your final image is as minimal as possible, you should use a multi-stage build. All stages in your Dockerfile should use a hardened image. While intermediary stages will typically use images tagged as dev, your final runtime stage should use a non-dev image variant.
    
4. **Install additional packages**
    
    Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to install additional packages in your Dockerfile. Inspect the image variants to identify which packages are already installed.
    
    Only images tagged as dev typically have package managers. You should use a multi-stage Dockerfile to install the packages. Install the packages in the build stage that uses a dev image. Then, if needed, copy any necessary artifacts to the runtime stage that uses a non-dev image.
    
    For Alpine-based images, you can use apk to install packages. For Debian-based images, you can use apt-get to install packages.

## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for debugging applications built with Docker Hardened Images is to use [Docker Debug](https://docs.docker.com/engine/reference/commandline/debug/) to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so your application running as the nonroot user can access them.

**Loki-specific permission considerations:**
- Ensure data directories (`/loki`, `/loki/chunks`, `/loki/index`) are writable by nonroot user
- Configuration files should be readable by nonroot user
- If mounting volumes, set appropriate ownership:
```bash
  chown -R 65532:65532 /path/to/loki-data
```

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. Loki's default port 3100 is above 1024, so this is not typically an issue.

### No shell

By default, image variants intended for runtime don't contain a shell. Use dev images in build stages to run shell commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.
```bash
# Inspect the entry point
docker inspect <your-namespace>/dhi-loki:3.5.8 | grep -A 5 "Entrypoint"
```
