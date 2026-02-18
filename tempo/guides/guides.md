# Tempo

## How to use this image

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/tempo:<tag>`
- Mirrored image: `<your-namespace>/dhi-tempo:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

## What's included in this Tempo image

Grafana Tempo is an open source, high-scale distributed tracing backend designed for simplicity and cost-efficiency. It stores trace data in object storage, making it significantly cheaper to operate than alternatives that require databases like Cassandra or Elasticsearch. Tempo integrates seamlessly with Grafana, Prometheus, and Loki, and supports popular tracing formats including OpenTelemetry, Jaeger, and Zipkin.

This Docker Hardened Image includes:

- Tempo binary for distributed trace ingestion, storage, and querying
- Support for OpenTelemetry (gRPC/HTTP), Jaeger, and Zipkin protocols
- TraceQL query language for trace-first queries
- Metrics generation from traces
- Standard TLS certificates

## Upstream image (`grafana/tempo`) vs Docker Hardened Image (`dhi.io/tempo`)

| Feature                | Upstream (`grafana/tempo`)        | DHI (`dhi.io/tempo`)                     |
| :--------------------- | :-------------------------------- | :--------------------------------------- |
| Base image             | Alpine/Distroless                 | Docker Hardened base                     |
| User                   | UID 10001                         | nonroot                                  |
| Shell                  | No                                | No (runtime) / Yes (dev)                 |
| Package manager        | No                                | No (runtime) / Yes (dev)                 |
| CVE scanning           | Standard                          | Zero-known CVEs at publish               |
| SBOM                   | Not included                      | Included with signed provenance          |
| VEX metadata           | Not included                      | Included                                 |
| FIPS variant           | No                                | Yes                                      |
| Supply chain security  | Standard                          | Signed provenance and attestation        |
| Update cadence         | Community-driven                  | Continuous security patching             |

### Why no shell or package manager?

Docker Hardened Images intended for runtime don't include a shell or package manager. This reduces the attack surface by
eliminating tools that could be exploited in a compromised container. The result is a smaller, more secure image that
meets compliance requirements for production environments.

For debugging, use one of these alternatives:

- [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach a shell session to a running container
- `kubectl debug` for Kubernetes environments
- Dev image variants (tagged with `dev`) that include a shell and package manager for development use

## Start a Tempo instance

To start a Tempo instance, run the following command. Replace `<tag>` with the image variant you want to run.

```bash
docker run dhi.io/tempo:2
```

> **Note:** Tempo requires a configuration file to start. See the common use cases below for working configuration
> examples.

## Common Tempo use cases

### Basic Tempo with local storage

Create a minimal Tempo configuration for local development with trace data stored on disk.

1. Create the Tempo configuration file:

```yaml
# tempo.yaml
stream_over_http_enabled: true

server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
    wal:
      path: /var/tempo/wal
```

2. Start Tempo with the configuration:

```bash
docker run -d --name tempo \
  -p 3200:3200 \
  -p 4317:4317 \
  -p 4318:4318 \
  -v $(pwd)/tempo.yaml:/etc/tempo.yaml \
  -v tempo-data:/var/tempo \
  dhi.io/tempo:2 \
  -config.file=/etc/tempo.yaml
```

3. Verify Tempo is running:

```bash
curl http://localhost:3200/ready
```

A successful response returns `ready`.

### Tempo with Grafana using Docker Compose

Deploy a complete tracing stack with Tempo and Grafana for trace visualization.

1. Create the Tempo configuration file (`tempo.yaml`) as shown in the previous use case.

2. Create the Grafana datasource configuration:

```yaml
# grafana-datasources.yaml
apiVersion: 1
datasources:
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    isDefault: true
```

3. Create a Docker Compose file:

```yaml
# compose.yaml
services:
  tempo:
    image: dhi.io/tempo:2
    command: ["-config.file=/etc/tempo.yaml"]
    ports:
      - "3200:3200"   # Tempo API
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
    volumes:
      - ./tempo.yaml:/etc/tempo.yaml
      - tempo-data:/var/tempo

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: Admin
    volumes:
      - ./grafana-datasources.yaml:/etc/grafana/provisioning/datasources/datasources.yaml
    depends_on:
      - tempo

volumes:
  tempo-data:
```

4. Start the stack:

```bash
docker compose up -d
```

5. Access Grafana at `http://localhost:3000` and navigate to **Explore > Tempo** to query traces.

### Tempo with multi-protocol ingestion

Configure Tempo to accept traces from OpenTelemetry, Jaeger, and Zipkin protocols simultaneously.

1. Create the Tempo configuration file:

```yaml
# tempo-multi.yaml
stream_over_http_enabled: true

server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"
    jaeger:
      protocols:
        thrift_http:
          endpoint: "0.0.0.0:14268"
        grpc:
          endpoint: "0.0.0.0:14250"
    zipkin:
      endpoint: "0.0.0.0:9411"

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
    wal:
      path: /var/tempo/wal
```

2. Start Tempo with all protocol ports exposed:

```bash
docker run -d --name tempo \
  -p 3200:3200 \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 9411:9411 \
  -p 14268:14268 \
  -v $(pwd)/tempo-multi.yaml:/etc/tempo.yaml \
  -v tempo-data:/var/tempo \
  dhi.io/tempo:2 \
  -config.file=/etc/tempo.yaml
```

This configuration allows you to send traces using any of the following endpoints:

| Protocol              | Port  | Endpoint                              |
| :-------------------- | :---- | :------------------------------------ |
| OTLP gRPC             | 4317  | `localhost:4317`                      |
| OTLP HTTP             | 4318  | `http://localhost:4318/v1/traces`     |
| Jaeger Thrift HTTP    | 14268 | `http://localhost:14268/api/traces`   |
| Zipkin                | 9411  | `http://localhost:9411/api/v2/spans`  |
| Tempo API / Query     | 3200  | `http://localhost:3200`               |

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

- FIPS variants include `fips` in the variant name and tag. They come in both runtime and build-time variants. These
  variants use cryptographic modules that have been validated under FIPS 140, a U.S. government standard for secure
  cryptographic operations. For example, usage of MD5 fails in FIPS variants.

| Variant      | Tag Example            | User    | Shell | Use Case                       |
| :----------- | :--------------------- | :------ | :---- | :----------------------------- |
| Runtime      | `2`                    | nonroot | No    | Production deployment          |
| Dev          | `2-dev`                | root    | Yes   | Development and debugging      |
| FIPS         | `2-fips`               | nonroot | No    | FIPS-compliant environments    |
| FIPS Dev     | `2-fips-dev`           | root    | Yes   | FIPS development               |

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

For Tempo specifically, the data directory `/var/tempo` must be writable by the nonroot user. When using Docker volumes,
this is handled automatically. When bind-mounting host directories, ensure correct ownership:

```bash
chown -R 65532:65532 ./tempo-data
```

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to
privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues,
configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on
the host. For example, `docker run -p 80:8080 my-image` will work because the port inside the container is 8080, and
`docker run -p 80:81 my-image` won't work because the port inside the container is 81.

Tempo's default ports (3200, 4317, 4318, 9411, 14268) are all above 1024, so no privileged port issues arise with the
default configuration.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev` images in build stages to run shell
commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers
with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect`
to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.

For Tempo, the entrypoint is the `/tempo` binary. Pass configuration using the `-config.file` flag:

```bash
docker run dhi.io/tempo:2 -config.file=/etc/tempo.yaml
```
