## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/airflow:<tag>`
- Mirrored image: `<your-namespace>/dhi-airflow:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

This guide provides practical examples for using the Apache Airflow Hardened Image for workflow orchestration.

## What's included in this Airflow image

This Docker Hardened Airflow image provides Apache Airflow in three variants:

- **Core (default) variant**: A minimal runtime image with Airflow core components, essential Python runtime dependencies, no provider packages, and no shell or package management tools.
- **Dev variant (`-dev`)**: A build-time image with package management tools (pip), shell access (bash/sh), and runs as root user for installing packages.
- **FIPS variant (`-fips`)**: A runtime image with FIPS-validated cryptographic modules, no shell or package management tools, and runs as nonroot user.

## Start an Airflow container

```bash
docker run -it --rm -p 8080:8080 -e AIRFLOW__API_AUTH__JWT_SECRET=test dhi.io/airflow:3.1.6-python3.12 api-server
```

> **Note:** This command is for testing purposes only. It will generate and print the admin username and password for logging into the web interface.

## Common use cases

### Run with Docker Compose

```bash
cat <<EOF > docker-compose.yml
services:
  airflow-init:
    image: dhi.io/airflow:3.1.6-python3.12
    command: ["db", "migrate"]
    environment:
      - AIRFLOW__API_AUTH__JWT_SECRET=your-secret-key
    volumes:
      - airflow-data:/opt/airflow

  airflow:
    image: dhi.io/airflow:3.1.6-python3.12
    command: ["api-server"]
    ports:
      - "8080:8080"
    environment:
      - AIRFLOW__API_AUTH__JWT_SECRET=your-secret-key
    volumes:
      - airflow-data:/opt/airflow
    depends_on:
      airflow-init:
        condition: service_completed_successfully

volumes:
  airflow-data:
EOF
```

Start the stack:

```console
$ docker compose up -d
```

Verify the API:

```console
$ curl http://localhost:8080/api/v2/version
{"version":"3.1.6","git_version":null}
```

### Run with Docker Compose (Full Stack with PostgreSQL and Redis)

For production-like setups, you need to install provider packages. First, create a custom image with providers.

Create a directory structure:

```console
$ mkdir -p airflow-dhi-test/dags
$ cd airflow-dhi-test
```

Create a sample DAG file:

```bash
cat <<EOF > dags/example_dag.py
from airflow import DAG
from airflow.operators.empty import EmptyOperator
from datetime import datetime

with DAG(
    dag_id="example_dag",
    start_date=datetime(2024, 1, 1),
    schedule=None,
) as dag:
    task1 = EmptyOperator(task_id="task1")
EOF
```

Create Dockerfile with providers:

```bash
cat <<EOF > Dockerfile
# syntax=docker/dockerfile:1

# Stage 1: Install providers using dev variant
FROM dhi.io/airflow:3.1.6-python3.12-dev AS provider-build
WORKDIR /opt/airflow
RUN pip install \
    --prefix /opt/airflow-providers \
    apache-airflow-providers-postgres \
    apache-airflow-providers-celery \
    apache-airflow-providers-redis

# Stage 2: Runtime image with providers
FROM dhi.io/airflow:3.1.6-python3.12 AS runtime
COPY --from=provider-build /opt/airflow-providers /opt/airflow
COPY dags/ /opt/airflow/dags/
EOF
```

Build the custom image:

```console
$ docker build -t my-airflow-dhi .
```

Verify providers are installed:

```console
$ docker run --rm my-airflow-dhi providers list
package_name                           | version
=======================================+========
apache-airflow-providers-celery        | 3.15.1
apache-airflow-providers-postgres      | 6.5.2
apache-airflow-providers-redis         | 4.4.2
```

Create Docker Compose for full stack:

```bash
cat <<EOF > docker-compose.yml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "airflow"]
      interval: 5s
      retries: 5

  redis:
    image: redis:7
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 5

  airflow-init:
    image: my-airflow-dhi
    command: ["db", "migrate"]
    environment:
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow
      - AIRFLOW__API_AUTH__JWT_SECRET=your-secret-key
    depends_on:
      postgres:
        condition: service_healthy

  airflow-webserver:
    image: my-airflow-dhi
    command: ["api-server"]
    ports:
      - "8080:8080"
    environment:
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow
      - AIRFLOW__API_AUTH__JWT_SECRET=your-secret-key
    depends_on:
      airflow-init:
        condition: service_completed_successfully

  airflow-scheduler:
    image: my-airflow-dhi
    command: ["scheduler"]
    environment:
      - AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow
      - AIRFLOW__API_AUTH__JWT_SECRET=your-secret-key
    depends_on:
      airflow-init:
        condition: service_completed_successfully

volumes:
  postgres-data:
EOF
```

Start the full stack:

```console
$ docker compose up -d
```

Verify all services are running:

```console
$ docker compose ps
NAME                                       IMAGE            COMMAND                  SERVICE             STATUS
airflow-compose-test-airflow-scheduler-1   my-airflow-dhi   "airflow scheduler"      airflow-scheduler   Up
airflow-compose-test-airflow-webserver-1   my-airflow-dhi   "airflow api-server"     airflow-webserver   Up
airflow-compose-test-postgres-1            postgres:16      "docker-entrypoint.s…"   postgres            Up (healthy)
airflow-compose-test-redis-1               redis:7          "docker-entrypoint.s…"   redis               Up (healthy)
```

Verify the API:

```console
$ curl http://localhost:8080/api/v2/version
{"version":"3.1.6","git_version":null}
```

List DAGs:

```console
$ docker compose exec airflow-webserver airflow dags list
dag_id      | fileloc                          | owners  | is_paused
============+==================================+=========+==========
example_dag | /opt/airflow/dags/example_dag.py | airflow | True
```

### Use Airflow in Kubernetes

To use the Airflow hardened image in Kubernetes, [set up authentication](https://docs.docker.com/dhi/how-to/k8s/)
and update your Kubernetes deployment.

```bash
cat <<EOF > airflow.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: airflow
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: airflow
  template:
    metadata:
      labels:
        app: airflow
    spec:
      containers:
        - name: airflow
          image: dhi.io/airflow:3.1.6-python3.12
          args:
            - api-server
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: AIRFLOW__API_AUTH__JWT_SECRET
              value: "your-secret-key"
      imagePullSecrets:
        - name: <your-registry-secret>
---
apiVersion: v1
kind: Service
metadata:
  name: airflow
  namespace: default
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: airflow
EOF
```

Then apply the manifest to your Kubernetes cluster:

```console
$ kubectl apply -n default -f airflow.yaml
```

Access the web interface:

```console
$ kubectl port-forward -n default deployment/airflow 8080:8080
```

Then visit http://localhost:8080 in your browser.

For examples of how to configure Airflow itself, see the
[Apache Airflow documentation](https://airflow.apache.org/docs/).

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature         | Non-hardened Airflow                | Docker Hardened Airflow                                    |
| --------------- | ----------------------------------- | ---------------------------------------------------------- |
| Base image      | Debian with full utilities          | Debian hardened base                                       |
| Security        | Standard image with basic utilities | Hardened build with security patches and security metadata |
| Shell access    | Shell (`/bin/bash`) available       | No shell (runtime variants)                                |
| Package manager | pip available                       | No package manager (runtime variants)                      |
| User            | Runs as `airflow` user              | Runs as `airflow` user (nonroot)                           |
| Attack surface  | Full OS utilities and tools         | Only Airflow binaries, no additional utilities             |
| Debugging       | Full shell and utilities            | Use Docker Debug or image mount for troubleshooting        |

### Why no shell or package manager?

Docker Hardened Images prioritize security through minimalism:

- Reduced attack surface: Fewer binaries mean fewer potential vulnerabilities
- Immutable infrastructure: Runtime containers shouldn't be modified after deployment
- Compliance ready: Meets strict security requirements for regulated environments

The hardened images intended for runtime don't contain a shell nor any tools for debugging. Common debugging methods for
applications built with Docker Hardened Images include:

- [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to containers
- Docker's Image Mount feature to mount debugging tools
- Ecosystem-specific debugging approaches

Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer
that only exists during the debugging session.

For example, you can use Docker Debug:

```console
$ docker run -d --name airflow-test dhi.io/airflow:3.1.6-python3.12 standalone
$ docker debug airflow-test
```

Inside the debug session:

```console
docker > cat /etc/os-release
NAME="Docker Hardened Images (Debian)"
ID=debian
VERSION_ID=13
VERSION_CODENAME=trixie
PRETTY_NAME="Docker Hardened Images/Debian GNU/Linux 13 (trixie)"
```

## Image variants

Docker Hardened Images come in different variants depending on their intended use. Image variants are identified by
their tag.

### Runtime variants

Runtime variants are designed to run your application in production. These images are intended to be used either
directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

- Run as the `airflow` nonroot user
- Do not include a shell or a package manager
- Contain only the minimal set of libraries needed to run Airflow

Available runtime tags: `3.1.6-python3.12`, `3.1-debian13`, `3-python3.12`, `3.1`, `3-debian13`

### Dev variants

Dev variants include `dev` in the tag name and are intended for use in the first stage of a multi-stage Dockerfile.
These images typically:

- Run as the root user
- Include a shell and package manager (pip)
- Are used to install Airflow providers and dependencies

Available dev tags: `3.1.6-python3.12-dev`, `3.1-dev`, `3-debian13-dev`, `3.1.6-dev`

To view the image variants and get more information about them, select the **Tags** tab for this repository, and then
select a tag.

### FIPS variants

FIPS variants include `fips` in the variant name and tag. These variants use cryptographic modules that have been
validated under FIPS 140, a U.S. government standard for secure cryptographic operations. Docker Hardened Airflow
images include FIPS-compliant variants for environments requiring Federal Information Processing Standards compliance.

Available FIPS tags: `3.1.6-fips`, `3.1.6-python3.12-debian13-fips`, `3.1-fips`, `3-python3.12-fips`, `3.1.6-python3.12-debian13-fips-dev`, `3.1-fips-dev`, `3-fips-dev`

#### Steps to verify FIPS:

```shell
# Compare image sizes (FIPS variants are larger due to FIPS crypto libraries)
$ docker images | grep airflow

# Verify FIPS compliance using image labels
$ docker inspect dhi.io/airflow:3.1.6-fips \
  --format '{{index .Config.Labels "com.docker.dhi.compliance"}}'
fips
```

#### Runtime requirements specific to FIPS:

- FIPS mode enforces stricter cryptographic standards
- Use FIPS variants when connecting to databases with FIPS-compliant TLS
- Required for deployments in US government or regulated environments
- Only FIPS-approved cryptographic algorithms are available for TLS connections

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the
base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the
following table of migration notes:

| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image         | Replace your base images in your Dockerfile with a Docker Hardened Image.                                                                                                                                                                                                                                                    |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a dev tag.                                                                                                                                                                                                    |
| Non-root user      | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user.                                                                                                                                                                   |
| Multi-stage build  | Utilize images with a dev tag for build stages and non-dev images for runtime. For binary executables, use a static image for runtime.                                                                                                                                                                                       |
| TLS certificates   | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates.                                                                                                                                                                                                           |
| Ports              | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. |
| Entry point        | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.                                                                                                                                  |
| No shell           | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage.                                                                                                                                                  |

The following steps outline the general migration process.

1. **Find hardened images for your app.**

   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.

1. **Update the base image in your Dockerfile.**

   Update the base image in your application's Dockerfile to the hardened image you found in the previous step. For
   framework images, this is typically going to be an image tagged as dev because it has the tools needed to install
   packages and dependencies.

1. **For multi-stage Dockerfiles, update the runtime image in your Dockerfile.**

   To ensure that your final image is as minimal as possible, you should use a multi-stage build. All stages in your
   Dockerfile should use a hardened image. While intermediary stages will typically use images tagged as dev, your final
   runtime stage should use a non-dev image variant.

1. **Install additional packages**

   Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to
   install additional packages in your Dockerfile. Inspect the image variants to identify which packages are already
   installed.

   Only images tagged as dev typically have package managers. You should use a multi-stage Dockerfile to install the
   packages. Install the packages in the build stage that uses a dev image. Then, if needed, copy any necessary
   artifacts to the runtime stage that uses a non-dev image.

   For Alpine-based images, you can use apk to install packages. For Debian-based images, you can use apt-get to install
   packages.

## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for
debugging applications built with Docker Hardened Images is to use
[Docker Debug](https://docs.docker.com/engine/reference/commandline/debug/) to attach to these containers. Docker Debug
provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only
exists during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot user. Ensure that necessary files and directories are
accessible to the nonroot user. You may need to copy files to different directories or change permissions so your
application running as the nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to
privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10.

### No shell

By default, image variants intended for runtime don't contain a shell. Use dev images in build stages to run shell
commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers
with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect`
to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.
