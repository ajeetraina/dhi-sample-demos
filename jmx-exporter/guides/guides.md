## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/<repository>:<tag>`
- Mirrored image: `<your-namespace>/dhi-<repository>:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

## What's included in this JMX Exporter image

This Docker Hardened JMX Exporter image includes:

- JMX Prometheus Standalone JAR (`jmx_prometheus_standalone.jar`) version 1.5.0, located at `/opt/jmx-exporter/`
- JMX Prometheus Java Agent JAR (`jmx_prometheus_javaagent.jar`) at `/opt/jmx-exporter/jmx_prometheus_javaagent.jar` for
  in-process metric collection
- Eclipse Temurin JRE 21 (`jre-21.0.10+7`) at `/opt/java/openjdk/21-jre`

## Run JMX Exporter

### Basic usage

By default, this image runs JMX Exporter in standalone mode using the bundled example configuration. To start the
exporter and expose metrics on port 5556, run the following command:

```bash
$ docker run --rm -p 5556:5556 dhi.io/jmx-exporter:<tag>
```

You can verify the exporter is running by querying its metrics or health endpoints:

```bash
curl localhost:5556/metrics
curl localhost:5556/-/healthy
```

The `/metrics` endpoint returns Prometheus-format metrics. The `/-/healthy` endpoint returns `Exporter is healthy.` when
the exporter is running correctly.

> **Note:** At startup, the exporter logs `OpenTelemetry enabled [false]` by default. OpenTelemetry output must be
> explicitly enabled in your configuration file. See the
> [upstream documentation](https://prometheus.github.io/jmx_exporter/) for details.

### Run in standalone mode with a custom configuration

To run JMX Exporter with your own configuration file, mount it into the container and pass it as a command argument:

```bash
$ docker run --rm -p 5556:5556 \
  -v /path/to/your/jmx_exporter_config.yaml:/etc/jmx_exporter_config.yaml \
  dhi.io/jmx-exporter:1 \
  5556 /etc/jmx_exporter_config.yaml
```

This command binds host port 5556 to container port 5556 and mounts your configuration file into the container.

### Run JMX Exporter as a Java Agent

In addition to standalone mode, the image includes the Java Agent JAR at
`/opt/jmx-exporter/jmx_prometheus_javaagent.jar`. You can copy this artifact into your own application image or create a
customized DHI to run JMX Exporter as an in-process Java agent.

The Java Agent supports both HTTP (default) and OpenTelemetry output modes, configured in your JMX Exporter
configuration file. See the [upstream documentation](https://prometheus.github.io/jmx_exporter/) for details.

Example multi-stage Dockerfile that copies the agent into your application image:

```dockerfile
FROM dhi.io/jmx-exporter:1 AS jmx-agent

FROM dhi.io/your-app-image:<tag>
COPY --from=jmx-agent /opt/jmx-exporter/jmx_prometheus_javaagent.jar /opt/jmx-exporter/jmx_prometheus_javaagent.jar
COPY jmx_exporter_config.yaml /etc/jmx_exporter_config.yaml

ENV JAVA_OPTS="-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=5556:/etc/jmx_exporter_config.yaml"
```

## Common JMX Exporter use cases

### Standalone exporter with a sample JVM application

Use Docker Compose to run JMX Exporter alongside a JVM application that exposes JMX metrics. Save the following as
`compose.yaml`:

```yaml
services:
  jmx-exporter:
    image: dhi.io/jmx-exporter:1
    container_name: jmx-exporter
    ports:
      - "5556:5556"
    volumes:
      - ./config.yaml:/opt/jmx-exporter/config.yaml
    command:
      - "5556"
      - config.yaml
    networks:
      - metrics
    depends_on:
      - example-app

  example-app:
    build: ./SimpleJMXApp
    container_name: example-app
    ports:
      - "9999:9999"
    command:
      - "java"
      - "-classpath"
      - "."
      - "-Dcom.sun.management.jmxremote=true"
      - "-Dcom.sun.management.jmxremote.authenticate=false"
      - "-Dcom.sun.management.jmxremote.local.only=false"
      - "-Dcom.sun.management.jmxremote.ssl=false"
      - "-Dcom.sun.management.jmxremote.port=9999"
      - "-Dcom.sun.management.jmxremote.rmi.port=9999"
      - "-Djava.rmi.server.hostname=example-app"
      - "SimpleJMXApp"
    networks:
      - metrics

networks:
  metrics:
    driver: bridge
```

Save the following as `config.yaml` in the same directory:

```yaml
jmxUrl: service:jmx:rmi:///jndi/rmi://example-app:9999/jmxrmi
startDelaySeconds: 5
ssl: false
lowercaseOutputName: false
lowercaseOutputLabelNames: false
rules:
  - pattern: ".*"
```

> **Important:** When running JMX Exporter in Docker Compose, use `jmxUrl` with the full RMI service URL instead of
> `hostPort`. The full `jmxUrl` format resolves correctly across Docker networks, whereas `hostPort` can fail silently
> due to RMI handshake issues between containers. The format is:
> `service:jmx:rmi:///jndi/rmi://<service-name>:<port>/jmxrmi`

Start the services:

```bash
docker compose up
```

Verify metrics are being scraped successfully:

```bash
curl localhost:5556/metrics | grep jmx_scrape_error
curl localhost:5556/-/healthy
```

A successful scrape shows `jmx_scrape_error 0.0` and real JVM metrics such as `java_lang_Threading_ThreadCount`,
`java_lang_OperatingSystem_SystemLoadAverage`, and `java_lang_Runtime_Uptime` in the output.

This example defines two services: `jmx-exporter`, which runs the standalone exporter listening on port 5556, and
`example-app`, a sample Java application exposing JMX metrics on port 9999 over RMI.

### Standalone exporter in Kubernetes

Deploy JMX Exporter in Kubernetes using a Deployment and a ConfigMap for the configuration. The following example shows
a minimal setup that scrapes a JVM application running in the same namespace.

First, create a ConfigMap for your JMX Exporter configuration. The configuration must include either `hostPort` or
`jmxUrl` to specify which JVM to scrape:

```bash
kubectl create configmap jmx-exporter-config \
  --from-file=config.yaml=/path/to/your/jmx_exporter_config.yaml
```

Alternatively, define the ConfigMap inline in your manifest:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jmx-exporter-config
  namespace: default
data:
  config.yaml: |
    hostPort: your-jvm-service:9999
    startDelaySeconds: 0
    ssl: false
    lowercaseOutputName: false
    lowercaseOutputLabelNames: false
    rules:
      - pattern: ".*"
```

Then apply the following Deployment and Service manifests:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jmx-exporter
  namespace: default
  labels:
    app: jmx-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jmx-exporter
  template:
    metadata:
      labels:
        app: jmx-exporter
    spec:
      containers:
      - name: jmx-exporter
        image: dhi.io/jmx-exporter:1
        args:
          - "5556"
          - /etc/jmx-exporter/config.yaml
        ports:
        - containerPort: 5556
          name: metrics
        securityContext:
          runAsNonRoot: true
          runAsUser: 65532
          allowPrivilegeEscalation: false
        resources:
          requests:
            cpu: "500m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
        volumeMounts:
        - name: config
          mountPath: /etc/jmx-exporter
      volumes:
      - name: config
        configMap:
          name: jmx-exporter-config
---
apiVersion: v1
kind: Service
metadata:
  name: jmx-exporter
  namespace: default
  labels:
    app: jmx-exporter
spec:
  selector:
    app: jmx-exporter
  ports:
  - name: metrics
    port: 5556
    targetPort: 5556
```

### Exporter with OpenTelemetry output

JMX Exporter supports OpenTelemetry as an output mode in addition to the default HTTP/Prometheus format. To enable
OpenTelemetry output, configure the `openTelemetry` section in your configuration file and pass it to the container:

```bash
$ docker run --rm -p 5556:5556 \
  -v /path/to/otel_config.yaml:/etc/jmx_exporter_config.yaml \
  dhi.io/jmx-exporter:1 \
  5556 /etc/jmx_exporter_config.yaml
```

## Image variants

Docker Hardened Images come in different variants depending on their intended use. The following variants are available
for this image:

### Runtime variants

Runtime variants are designed to run your application in production. These images are intended to be used either
directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

- Run as a nonroot user
- Do not include a shell, `curl`, `wget`, or a package manager
- Contain only the minimal set of libraries needed to run the exporter

### FIPS variants

FIPS variants include `fips` in the tag name and come in both runtime and build-time variants. They use cryptographic
modules validated under FIPS 140, a U.S. government standard for secure cryptographic operations. Both FIPS variants for
this image are also STIG-compliant at 100%, making them suitable for government and regulated industry deployments.

To use the FIPS-compliant runtime image:

```bash
$ docker run --rm -p 5556:5556 \
  -v /path/to/your/jmx_exporter_config.yaml:/etc/jmx_exporter_config.yaml \
  dhi.io/jmx-exporter:1-debian13-fips \
  5556 /etc/jmx_exporter_config.yaml
```

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the
base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the
following table of migration notes.

| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
| :----------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image         | Replace your base images in your Dockerfile with a Docker Hardened Image.                                                                                                                                                                                                                                                    |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a `dev` tag.                                                                                                                                                                                                  |
| Nonroot user       | By default, non-dev images, intended for runtime, run as a nonroot user. Ensure that necessary files and directories are accessible to that user.                                                                                                                                                                            |
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

1. Install additional packages.

   Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to
   install additional packages in your Dockerfile. To view if a package manager is available for an image variant,
   select the **Tags** tab for this repository. To view what packages are already installed in an image variant, select
   the **Tags** tab for this repository, and then select a tag.

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

By default, image variants intended for runtime run as a nonroot user. Ensure that necessary files and directories are
accessible to that user. You may need to copy files to different directories or change permissions so your application
running as a nonroot user can access them.

To view the user for an image variant, select the **Tags** tab for this repository.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to
privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues,
configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on
the host. For example, `docker run -p 80:8080 my-image` will work because the port inside the container is 8080, and
`docker run -p 80:81 my-image` won't work because the port inside the container is 81.

The default JMX Exporter port (5556) is already above the privileged port threshold and does not require additional
configuration.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev` images in build stages to run shell
commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers
with no shell.

To see if a shell is available in an image variant and which one, select the **Tags** tab for this repository.

### No curl or wget

The DHI JMX Exporter runtime image does not include `curl`, `wget`, or other HTTP clients. Do not rely on these tools
for healthchecks or scripts that run inside the container. Use Docker Debug to install tools temporarily for debugging
purposes, or configure liveness and readiness probes using `exec`-based commands with `java` if available.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images.

To view the Entrypoint or CMD defined for an image variant, select the **Tags** tab for this repository, select a tag,
and then select the **Specifications** tab.
