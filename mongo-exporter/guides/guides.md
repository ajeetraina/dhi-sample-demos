# MongoDB Exporter Docker Hardened Images Guide

Before you can use any Docker Hardened Image, you must mirror the image repository from the catalog to your organization. To mirror the repository, select either **Mirror to repository** or **View in repository > Mirror to repository**, and then follow the on-screen instructions.


## Start a MongoDB Exporter instance

### Basic MongoDB Exporter instance

Run the following command and replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```bash
docker run -d \
  --name mongodb-exporter \
  -p 9216:9216 \
  <your-namespace>/dhi-mongodb-exporter:<tag> \
  --mongodb.uri=mongodb://localhost:27017
```

**Note:** This assumes MongoDB is running on `localhost`. If your MongoDB instance is on a different host, replace `localhost` with the appropriate hostname or IP address.

### MongoDB Exporter with authentication

If your MongoDB instance requires authentication, provide credentials in the connection URI:

```bash
docker run -d \
  --name mongodb-exporter \
  -p 9216:9216 \
  <your-namespace>/dhi-mongodb-exporter:<tag> \
  --mongodb.uri=mongodb://admin:secure_password@mongodb:27017/admin
```

### Using environment variables

You can also configure MongoDB Exporter using environment variables:

```bash
docker run -d \
  --name mongodb-exporter \
  -p 9216:9216 \
  -e MONGODB_URI=mongodb://admin:secure_password@mongodb:27017/admin \
  <your-namespace>/dhi-mongodb-exporter:<tag>
```

Available environment variables:
- `MONGODB_URI`: MongoDB connection URI (e.g., `mongodb://user:pass@host:27017/admin`)
- `MONGODB_USER`: MongoDB username (alternative to including in URI)
- `MONGODB_PASSWORD`: MongoDB password (alternative to including in URI)

## Common MongoDB Exporter use cases

### Complete monitoring setup with MongoDB

This example shows how to set up MongoDB with authentication and MongoDB Exporter for monitoring:

```bash
# 1. Start MongoDB with authentication
docker network create mongo-monitoring

docker run -d \
  --name mongodb \
  --network mongo-monitoring \
  -v mongodb_data:/data/db \
  <your-namespace>/dhi-mongodb:<tag>-dev

sleep 7

# 2. Create admin user
docker exec mongodb mongosh --eval "
  db.getSiblingDB('admin').createUser({
    user: 'admin',
    pwd: 'secure_password',
    roles: [{role: 'root', db: 'admin'}]
  })
"

# 3. Enable authentication
docker stop mongodb && docker rm mongodb

docker volume create mongodb_config
docker run --rm -v mongodb_config:/c <your-namespace>/dhi-alpine-base:<tag> sh -c 'cat > /c/mongod.conf << "EOF"
net:
  bindIp: 0.0.0.0
storage:
  dbPath: /data/db
security:
  authorization: enabled
EOF'

docker run -d \
  --name mongodb \
  --network mongo-monitoring \
  -p 27017:27017 \
  -v mongodb_data:/data/db \
  -v mongodb_config:/etc/mongo:ro \
  <your-namespace>/dhi-mongodb:<tag>-dev \
  --config /etc/mongo/mongod.conf

sleep 7

# 4. Start MongoDB Exporter
docker run -d \
  --name mongodb-exporter \
  --network mongo-monitoring \
  -p 9216:9216 \
  <your-namespace>/dhi-mongodb-exporter:<tag> \
  --mongodb.uri=mongodb://admin:secure_password@mongodb:27017/admin \
  --collector.dbstats \
  --collector.collstats

# 5. Verify metrics are being exported
curl http://localhost:9216/metrics
```

### Advanced configuration options

The MongoDB Exporter supports various command-line flags to customize its behavior:

```bash
docker run -d \
  --name mongodb-exporter \
  -p 9216:9216 \
  <your-namespace>/dhi-mongodb-exporter:<tag> \
  --mongodb.uri=mongodb://admin:secure_password@mongodb:27017/admin \
  --web.listen-address=:9216 \
  --web.telemetry-path=/metrics \
  --mongodb.connect-timeout-ms=5000 \
  --collector.dbstats \
  --collector.collstats \
  --collector.topmetrics \
  --collector.indexstats \
  --collector.replicasetstatus
```

**Common collectors:**
- `--collector.dbstats` - Database statistics
- `--collector.collstats` - Collection statistics
- `--collector.topmetrics` - Top command metrics
- `--collector.indexstats` - Index statistics
- `--collector.replicasetstatus` - Replica set status metrics

### Docker Compose example

Complete monitoring stack with MongoDB, MongoDB Exporter, and Prometheus:

```yaml

services:
  mongodb:
    image: <your-namespace>/dhi-mongodb:<tag>-dev
    container_name: mongodb
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: password
    volumes:
      - mongodb_data:/data/db
    networks:
      - monitoring

  mongodb-exporter:
    image: <your-namespace>/dhi-mongodb-exporter:<tag>
    container_name: mongodb-exporter
    ports:
      - "9216:9216"
    command:
      - --mongodb.uri=mongodb://admin:password@mongodb:27017/admin
      - --collector.dbstats
      - --collector.collstats
      - --collector.topmetrics
    depends_on:
      - mongodb
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    depends_on:
      - mongodb-exporter
    networks:
      - monitoring

volumes:
  mongodb_data:
  prometheus_data:

networks:
  monitoring:
    driver: bridge
```

**prometheus.yml configuration:**

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'mongodb-exporter'
    static_configs:
      - targets: ['mongodb-exporter:9216']
```

### Accessing metrics

Once the MongoDB Exporter is running, you can access the metrics:

```bash
# View all metrics
curl http://localhost:9216/metrics

# Filter specific metrics
curl http://localhost:9216/metrics | grep mongodb_up

# Check exporter health
curl http://localhost:9216/metrics | grep mongodb_exporter_build_info
```

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | MongoDB Exporter (Official) | Docker Hardened MongoDB Exporter |
|---------|---------------------------|----------------------------------|
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | No shell in runtime variants |
| Package manager | apt available | No package manager in runtime variants |
| User | Runs as specific user | Runs as nonroot user |
| Attack surface | Larger due to additional utilities | Minimal, only essential components |
| Debugging | Traditional shell debugging | Use Docker Debug or Image Mount for troubleshooting |
| Vulnerabilities | Varies by base image | None found (as per current scans) |

### Why no shell or package manager?

Docker Hardened Images prioritize security through minimalism:


The hardened images intended for runtime don't contain a shell nor any tools for debugging. Common debugging methods for applications built with Docker Hardened Images include:

- Docker Debug to attach to containers
- Docker's Image Mount feature to mount debugging tools
- Ecosystem-specific debugging approaches

Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Debugging examples

Using Docker Debug:

```bash
docker debug mongodb-exporter
```

Using Image Mount feature:

```bash
docker run --rm -it --pid container:mongodb-exporter \
  --mount=type=image,source=<your-namespace>/dhi-busybox,destination=/dbg,ro \
  <your-namespace>/dhi-mongodb-exporter:<tag> /dbg/bin/sh
```

## Image variants

Docker Hardened Images come in different variants depending on their intended use.

**Runtime variants** are designed to run your application in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Do not include a shell or a package manager
- Contain only the minimal set of libraries needed to run the app

**Build-time variants** typically include `dev` in the variant name and are intended for use in the first stage of a multi-stage Dockerfile. These images typically:

- Run as the root user
- Include a shell and package manager
- Are used to build or compile applications

**Note:** The MongoDB Exporter DHI currently only provides runtime variants as the exporter is distributed as a pre-built binary.

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the base image in your existing Dockerfile to a Docker Hardened Image.

### Migration notes

| Item | Migration note |
|------|---------------|
| Base image | Replace your base images in your Dockerfile with a Docker Hardened Image. |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a dev tag. |
| Non-root user | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. |
| Multi-stage build | Utilize images with a dev tag for build stages and non-dev images for runtime. For binary executables, use a static image for runtime. |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| Ports | Non-dev hardened images run as a nonroot user by default. MongoDB Exporter's default port 9216 works without issues as it's above 1024. |
| Entry point | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| No shell | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage. |

### Migration process

1. **Find hardened images for your app**

   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.

2. **Update deployment configuration**

   For MongoDB Exporter, you typically don't need a custom Dockerfile. Update your Docker Compose files, Kubernetes manifests, or Docker run commands to use the hardened image:

   ```bash
   # Before
   docker run -d -p 9216:9216 percona/mongodb_exporter:0.40 \
     --mongodb.uri=mongodb://localhost:27017

   # After
   docker run -d -p 9216:9216 <your-namespace>/dhi-mongodb-exporter:0.47.1-debian13 \
     --mongodb.uri=mongodb://localhost:27017
   ```

3. **Verify functionality**

   After migration, verify that:
   - The exporter connects to MongoDB successfully
   - Metrics are being exported correctly
   - Prometheus can scrape the metrics
   - No authentication issues exist

   ```bash
   # Test metrics endpoint
   curl http://localhost:9216/metrics | grep mongodb_up
   
   # Should return: mongodb_up 1
   ```

## Troubleshooting migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for debugging applications built with Docker Hardened Images is to use Docker Debug to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

```bash
docker debug mongodb-exporter
```

### Common issues

#### Connection failures

If the exporter can't connect to MongoDB:

1. Verify the MongoDB URI is correct
2. Ensure MongoDB is accessible from the exporter container
3. Check authentication credentials
4. Verify network connectivity

```bash
# Check exporter logs
docker logs mongodb-exporter

# Test network connectivity
docker exec mongodb-exporter ping mongodb  # Note: ping may not work in hardened images

# Verify MongoDB is accessible
docker exec mongodb mongosh --eval "db.version()"
```

#### No metrics appearing

If metrics aren't being exported:

1. Check if the exporter is running
2. Verify the web endpoint is accessible
3. Check for authentication errors

```bash
# Check if container is running
docker ps | grep mongodb-exporter

# Test metrics endpoint
curl http://localhost:9216/metrics

# Check specific MongoDB connectivity metric
curl http://localhost:9216/metrics | grep mongodb_up
```

#### Permissions

By default image variants intended for runtime, run as the nonroot user. This typically doesn't cause issues for MongoDB Exporter as it only needs network access and doesn't require file system writes.

#### Privileged ports

MongoDB Exporter uses port 9216 by default, which is above 1024, so there are no privileged port issues. If you need to customize the port, ensure you use a port above 1024:

#### No shell

By default, image variants intended for runtime don't contain a shell. For MongoDB Exporter, all configuration is done via command-line flags or environment variables, so shell access is rarely needed. Use Docker Debug to troubleshoot containers with no shell.

#### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your configuration if necessary:

