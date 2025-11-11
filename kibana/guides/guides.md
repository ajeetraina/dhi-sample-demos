## How to use this image

Before you can use any Docker Hardened Image, you must mirror the image repository from the catalog to your organization. To mirror the repository, select either **Mirror to repository** or **View in repository > Mirror to repository**, and then follow the on-screen instructions.

### Start a Kibana instance

Kibana requires a running Elasticsearch cluster to function. Kibana 9.2.0+ requires a **service account token** for authentication.

Run the following commands to start Elasticsearch and Kibana:
```bash
# Step 1: Create network
docker network create elastic-network

# Step 2: Create Elasticsearch configuration file
cat > elasticsearch.yml <<EOF
cluster.name: docker-cluster
discovery.type: single-node
EOF

# Step 3: Start Elasticsearch DHI with mounted config
docker run -d --name elasticsearch \
  --net elastic-network \
  -p 9200:9200 -p 9300:9300 \
  -v $(pwd)/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro \
  /dhi-elasticsearch:9.2.0

# Step 4: Wait for Elasticsearch to be ready (30-60 seconds)
sleep 30

# Step 5: Create Kibana service account token
docker exec elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token

# Output will show:
# SERVICE_TOKEN elastic/kibana/kibana-token = AAEAAWVsYXN0aWMva2liYW5hL2tpYmFuYS10b2tlbjp...
# Copy the token value after the "=" sign

# Step 6: Start Kibana with the service account token
docker run -d --name kibana \
  --net elastic-network \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS=https://elasticsearch:9200 \
  -e ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN= \
  -e ELASTICSEARCH_SSL_VERIFICATIONMODE=none \
  /dhi-kibana:9.2.0

# Step 7: Verify Kibana is running
curl http://localhost:5601/api/status
```

You can access Kibana via `http://localhost:5601`. 

**Important Notes:**
- Kibana 9.2.0+ no longer accepts the `elastic` superuser account
- You must use service account tokens as shown above
- Elasticsearch configuration requires a mounted config file (env vars don't work)

### Configure Kibana with Enrollment Token

When you start Elasticsearch for the first time, an enrollment token is automatically generated. You'll need this token to configure Kibana during initial setup.

To retrieve the enrollment token, run:
```bash
# Generate Kibana enrollment token from Elasticsearch
docker exec elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```

This token can be used during Kibana's initial setup when you first access `http://localhost:5601` in your browser. Alternatively, you can configure Kibana using the service account token as shown in the examples above.

## Common Kibana use cases

### Index sample data and visualize in Kibana

Once Kibana is running, you can index data in Elasticsearch and visualize it. Note that for API access, you'll need to use the service account token:
```bash
# Get your service token (if not saved from earlier)
SERVICE_TOKEN=$(docker exec elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens list | \
  grep "elastic/kibana" | awk '{print $1}')

# Index a sample document
curl -k -H "Authorization: Bearer $SERVICE_TOKEN" \
  -X POST "https://localhost:9200/sample-data/_doc/1?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Docker Hardened Images",
    "category": "security",
    "timestamp": "2025-01-15T10:00:00"
  }'

# Index more sample documents
curl -k -H "Authorization: Bearer $SERVICE_TOKEN" \
  -X POST "https://localhost:9200/sample-data/_doc/2?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Kibana Visualization",
    "category": "analytics",
    "timestamp": "2025-01-16T14:30:00"
  }'

# Search the data
curl -k -H "Authorization: Bearer $SERVICE_TOKEN" \
  -X GET "https://localhost:9200/sample-data/_search?pretty"

# Now open Kibana at http://localhost:5601
# Go to "Discover" to see your data
# Go to "Dashboard" to create visualizations
```

### Kibana with custom configuration

Use custom configuration files for advanced settings:
```bash
# Create Elasticsearch configuration
cat > elasticsearch.yml < kibana.yml <<EOF
server.host: "0.0.0.0"
server.port: 5601
elasticsearch.hosts: ["https://elasticsearch:9200"]
elasticsearch.serviceAccountToken: ""
elasticsearch.ssl.verificationMode: "none"
monitoring.ui.container.elasticsearch.enabled: true
EOF

# Start Elasticsearch with custom config
docker run -d --name elasticsearch \
  --net elastic-network \
  -p 9200:9200 -p 9300:9300 \
  -v $(pwd)/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro \
  /dhi-elasticsearch:9.2.0

# Wait and create service token
sleep 30
docker exec elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token

# Update kibana.yml with the token, then start Kibana
docker run -d --name kibana \
  --net elastic-network \
  -p 5601:5601 \
  -v $(pwd)/kibana.yml:/usr/share/kibana/config/kibana.yml:ro \
  /dhi-kibana:9.2.0
```

### Docker Compose example

To use Kibana with Elasticsearch DHI in a multi-service environment, create the following files:

**elasticsearch.yml:**
```yaml
cluster.name: docker-cluster
discovery.type: single-node
```

**docker-compose.yml:**
```yaml
version: '3'
services:
  elasticsearch:
    image: /dhi-elasticsearch:9.2.0
    volumes:
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - elastic

  kibana:
    image: /dhi-kibana:9.2.0
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=https://elasticsearch:9200
      - ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN=
      - ELASTICSEARCH_SSL_VERIFICATIONMODE=none
    depends_on:
      - elasticsearch
    networks:
      - elastic

networks:
  elastic:
    driver: bridge
```

**Setup steps:**
```bash
# Create elasticsearch.yml in the same directory as docker-compose.yml
cat > elasticsearch.yml <-elasticsearch-1 \
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token

# Copy the token output (after "=")
# Update docker-compose.yml with 

# (Optional) Generate enrollment token for browser setup
docker exec -elasticsearch-1 \
  /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana

# Start Kibana
docker compose up -d kibana

# Verify
curl http://localhost:5601/api/status
```

### Monitoring and observability stack

Deploy a production-ready Elastic Stack with resource limits:
```bash
# Create network
docker network create observability

# Create Elasticsearch configuration
cat > elasticsearch.yml <<EOF
cluster.name: observability-cluster
discovery.type: single-node

# JVM heap size will be set via ES_JAVA_OPTS environment variable
# Resource limits set at container level
EOF

# Start Elasticsearch with resource limits
docker run -d --name elasticsearch \
  --network observability \
  --memory="4g" \
  --cpus="2.0" \
  -p 9200:9200 -p 9300:9300 \
  -e "ES_JAVA_OPTS=-Xms2g -Xmx2g" \
  -v $(pwd)/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro \
  /dhi-elasticsearch:9.2.0

# Wait for Elasticsearch to start
sleep 30

# Create service account token
SERVICE_TOKEN=$(docker exec elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token | \
  grep "SERVICE_TOKEN" | awk '{print $NF}')

echo "Service Token: $SERVICE_TOKEN"

# Start Kibana with monitoring enabled
docker run -d --name kibana \
  --network observability \
  --memory="2g" \
  --cpus="1.0" \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS=https://elasticsearch:9200 \
  -e ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN="$SERVICE_TOKEN" \
  -e ELASTICSEARCH_SSL_VERIFICATIONMODE=none \
  -e MONITORING_UI_CONTAINER_ELASTICSEARCH_ENABLED=true \
  /dhi-kibana:9.2.0

# Check status
curl http://localhost:5601/api/status | grep -i overall
```

**Note:** The `ES_JAVA_OPTS` environment variable works because it's processed by the JVM, not by Elasticsearch's configuration system.

## Multi-stage Dockerfile integration

Kibana DHI images do NOT provide dev variants. For build stages that require shell access and package managers, use standard Docker Official Kibana images or Debian base images.
```dockerfile
# syntax=docker/dockerfile:1
# Build stage - Use standard base image (has shell and package managers)
FROM debian:bookworm-slim AS builder

USER root

# Install configuration tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create custom Elasticsearch configuration
RUN mkdir -p /app/config && \
    echo 'cluster.name: "custom-cluster"' > /app/config/elasticsearch.yml && \
    echo 'discovery.type: single-node' >> /app/config/elasticsearch.yml && \
    chown -R 1000:1000 /app

# Create custom Kibana configuration
RUN echo 'server.host: "0.0.0.0"' > /app/config/kibana.yml && \
    echo 'elasticsearch.hosts: ["https://elasticsearch:9200"]' >> /app/config/kibana.yml && \
    echo 'elasticsearch.ssl.verificationMode: "none"' >> /app/config/kibana.yml && \
    chown -R 65532:65532 /app/config/kibana.yml

# Runtime stage - Use Docker Hardened Images
FROM /dhi-elasticsearch:9.2.0 AS elasticsearch-runtime
COPY --from=builder --chown=elasticsearch:elasticsearch /app/config/elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml

FROM /dhi-kibana:9.2.0 AS kibana-runtime
COPY --from=builder --chown=nonroot:nonroot /app/config/kibana.yml /usr/share/kibana/config/kibana.yml
```

Build and run:
```bash
# Build images
docker build --target elasticsearch-runtime -t my-elasticsearch-app .
docker build --target kibana-runtime -t my-kibana-app .

# Run Elasticsearch
docker run -d --name my-elasticsearch \
  --net elastic-network \
  -p 9200:9200 -p 9300:9300 \
  my-elasticsearch-app

# Wait and create service token
sleep 30
SERVICE_TOKEN=$(docker exec my-elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token | \
  grep "SERVICE_TOKEN" | awk '{print $NF}')

# Run Kibana with service token
docker run -d --name my-kibana \
  --net elastic-network \
  -p 5601:5601 \
  -e ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN="$SERVICE_TOKEN" \
  my-kibana-app
```

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Docker Official Kibana | Docker Hardened Kibana |
|---------|------------------------|------------------------|
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | No shell in runtime variants |
| Package manager | apt/yum available | No package manager in runtime variants |
| User | Runs as kibana user | Runs as nonroot user (UID 65532) |
| Attack surface | Larger due to additional utilities | Minimal, only essential components |
| Debugging | Traditional shell debugging | Use Docker Debug or Image Mount for troubleshooting |
| Vulnerabilities | May contain CVEs in bundled utilities | Zero critical/high vulnerabilities |

### Authentication Changes in Kibana 9.2.0+

**Important:** Kibana 9.2.0 and later versions require service account tokens for authentication. The `elastic` superuser account is no longer supported for Kibana connections.

**Old method (no longer works):**
```bash
# ❌ This will fail in Kibana 9.2.0+
-e ELASTICSEARCH_USERNAME=elastic
-e ELASTICSEARCH_PASSWORD=<password>
```

**New method (required):**
```bash
# ✅ Use service account token
-e ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN=<token>
```

### Verify the differences yourself

Here are practical commands to verify the security improvements of Docker Hardened Kibana:

#### 1. Check user and shell access
```bash
# Docker Hardened Kibana - No shell, runs as nonroot user (UID 65532)
docker run --rm <your-namespace>/dhi-kibana:9.2.0 id
# Output: uid=65532(nonroot) gid=65532(nonroot) groups=65532(nonroot)

docker run --rm <your-namespace>/dhi-kibana:9.2.0 /bin/sh -c "echo test"
# Output: Error: executable file not found in $PATH
```

#### 2. Check for package manager
```bash
# Docker Hardened Kibana - No package manager
docker run --rm <your-namespace>/dhi-kibana:9.2.0 which apt
# Output: Error or no output (apt not found)
```

#### 3. Compare attack surface (installed packages)
```bash
# Docker Hardened Kibana - Minimal binaries only
docker run --rm <your-namespace>/dhi-kibana:9.2.0 ls /usr/bin | wc -l
# Output: Significantly fewer binaries
```

#### 4. Inspect image layers and size
```bash
# Pull the image
docker pull <your-namespace>/dhi-kibana:9.2.0

# Check image size
docker images | grep kibana

# Inspect layers
docker history <your-namespace>/dhi-kibana:9.2.0
```

#### 5. Scan for vulnerabilities
```bash
# Scan Docker Hardened Kibana
docker scout cves <your-namespace>/dhi-kibana:9.2.0
# Expected: Zero critical/high vulnerabilities
```

#### 6. Test debugging capabilities
```bash
# Start a Kibana container
docker run -d --name test-kibana \
  --net elastic-network \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS=https://elasticsearch:9200 \
  -e ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN=<YOUR-SERVICE-TOKEN> \
  -e ELASTICSEARCH_SSL_VERIFICATIONMODE=none \
  <your-namespace>/dhi-kibana:9.2.0

# Docker Hardened - Use Docker Debug for troubleshooting
docker debug test-kibana

# Inside the debug shell, you'll have access to tools like:
# - ps, top (process monitoring)
# - curl, wget (network testing)
# - vi, nano (file editing)
# - And many other debugging utilities
```

### Why no shell or package manager?

Docker Hardened Images prioritize security through minimalism:

- **Reduced attack surface**: Fewer binaries mean fewer potential vulnerabilities
- **Immutable infrastructure**: Runtime containers shouldn't be modified after deployment
- **Compliance ready**: Meets strict security requirements for regulated environments

The hardened images intended for runtime don't contain a shell nor any tools for debugging. Common debugging methods for applications built with Docker Hardened Images include:

- **Docker Debug** to attach to containers
- **Docker's Image Mount** feature to mount debugging tools
- **Ecosystem-specific debugging approaches**

Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

For example, you can use Docker Debug:
```bash
docker debug <container-name>
```

or mount debugging tools with the Image Mount feature:
```bash
docker run --rm -it --pid container:my-kibana \
  --mount=type=image,source=<your-namespace>/dhi-busybox,destination=/dbg,ro \
  <your-namespace>/dhi-kibana:9.2.0 /dbg/bin/sh
```

## Image variants

Docker Hardened Images come in different variants depending on their intended use.

**Runtime variants** are designed to run your application in production. These images are intended to be used either directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user (UID 65532)
- Do not include a shell or a package manager
- Contain only the minimal set of libraries needed to run the app

**Note**: Kibana DHI does NOT provide dev variants. For build stages requiring shell access or package managers, use standard Docker Official Kibana images or Debian base images.

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the following table of migration notes.

| Item | Migration note |
|:-----|:--------------|
| Base image | Replace your base images in your Dockerfile with a Docker Hardened Image. |
| Authentication | Kibana 9.2.0+ requires `ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN` instead of username/password. Create service account tokens using `elasticsearch-service-tokens`. |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a `dev` tag. |
| Non-root user | By default, non-dev images, intended for runtime, run as the nonroot user (UID 65532). Ensure that necessary files and directories are accessible to the nonroot user. |
| Multi-stage build | Utilize images with a `dev` tag for build stages and non-dev images for runtime. For binary executables, use a `static` image for runtime. |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| Ports | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. Kibana's default port 5601 is already non-privileged. |
| Entry point | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| No shell | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage. |

The following steps outline the general migration process.

1. **Find hardened images for your app.**

   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.

2. **Update the base image in your Dockerfile.**

   Update the base image in your application's Dockerfile to the hardened image you found in the previous step. For framework images, this is typically going to be an image tagged as `dev` because it has the tools needed to install packages and dependencies.

3. **For multi-stage Dockerfiles, update the runtime image in your Dockerfile.**

   To ensure that your final image is as minimal as possible, you should use a multi-stage build. All stages in your Dockerfile should use a hardened image. While intermediary stages will typically use images tagged as `dev`, your final runtime stage should use a non-dev image variant.

4. **Update authentication configuration.**

   For Kibana 9.2.0+, replace username/password authentication with service account tokens:
```bash
   # Create the service account token
   docker exec elasticsearch \
     /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token
   
   # Use the token in your configuration
   ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN=<token>
```

5. **Install additional packages**

   Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to install additional packages in your Dockerfile. Inspect the image variants to identify which packages are already installed.

   Only images tagged as `dev` typically have package managers. You should use a multi-stage Dockerfile to install the packages. Install the packages in the build stage that uses a `dev` image. Then, if needed, copy any necessary artifacts to the runtime stage that uses a non-dev image.

   For Alpine-based images, you can use `apk` to install packages. For Debian-based images, you can use `apt-get` to install packages.

## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for debugging applications built with Docker Hardened Images is to use [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Authentication issues

If Kibana fails to start with an error about the `elastic` user being forbidden:
```
Error: [config validation of [elasticsearch].username]: value of "elastic" is forbidden
```

This means you're using the old authentication method. Update your configuration to use service account tokens:
```bash
# Create service account token
docker exec elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token

# Use the token instead of username/password
-e ELASTICSEARCH_SERVICE_ACCOUNT_TOKEN=<token>
```

### Permissions

By default image variants intended for runtime, run as the nonroot user (UID 65532). Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so your application running as the nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. Kibana's default port (5601) is already non-privileged, so this shouldn't be an issue.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev` images in build stages to run shell commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.
