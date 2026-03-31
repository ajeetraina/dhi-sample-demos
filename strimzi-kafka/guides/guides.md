# Docker Hardened Image: strimzi-kafka

## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

| | Example |
|---|---|
| Public image | `dhi.io/strimzi-kafka:<tag>` |
| Mirrored image | `<your-namespace>/dhi-strimzi-kafka:<tag>` |

Before pulling images, authenticate to the registry:

```bash
docker login dhi.io
```

### What's included in this image

- Kafka broker and related binaries
- CIS benchmark compliance (runtime variant)
- FIPS 140, STIG, and CIS compliance (FIPS variant)

---

## Start a strimzi-kafka instance

Running a `strimzi-kafka` image starts a Kafka broker. This lets you explore included binaries or run typical Kafka commands.

Replace `<tag>` with the image variant you want to run:

```bash
docker run --rm dhi.io/strimzi-kafka:<tag> /opt/kafka/bin/kafka-server-start.sh --version
```

---

## Common use cases

### Single Kafka broker setup

<!-- Add single broker setup steps here -->

### Multiple broker configuration

<!-- Add multi-broker configuration steps here -->

### Deploy strimzi-kafka in Kubernetes

1. Follow the [DHI Kubernetes authentication instructions](https://docs.docker.com).

2. Create a namespace for Kafka:

    ```bash
    kubectl create namespace kafka
    ```

3. Create a deployment manifest (`kafka-deployment.yaml`) with `imagePullSecrets`:

    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: strimzi-kafka
      namespace: kafka
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: kafka
      template:
        metadata:
          labels:
            app: kafka
        spec:
          imagePullSecrets:
            - name: myregistrykey
          containers:
            - name: kafka
              image: dhi.io/strimzi-kafka:<tag>
              imagePullPolicy: Always
              securityContext:
                runAsUser: 65532  # nonroot user
              ports:
                - containerPort: 9092
    ```

4. Apply the deployment and verify the pods are running:

    ```bash
    kubectl apply -f kafka-deployment.yaml
    kubectl get pods -n kafka
    ```

---

## Docker Official Image vs Docker Hardened Image

| Feature | DOI (`strimzi/kafka`) | DHI (`dhi.io/strimzi-kafka`) |
|---|---|---|
| User | 1001 | nonroot |
| Shell | `/bin/bash` | None |
| Package manager | apt-get | None |
| Entrypoint | N/A | `/opt/kafka/bin/kafka-server-start.sh` |
| Uncompressed size | 629 MB | 565 MB |
| Zero CVE commitment | No | Yes |
| FIPS variant | No | Yes (FIPS + STIG + CIS) |
| Base OS | CentOS | Debian 13 |
| Compliance labels | None | CIS (runtime), FIPS+STIG+CIS (fips) |
| Architectures | amd64 | amd64, arm64 |

---

## Image variants

Image variants are identified by their tag.

| Variant | Description |
|---|---|
| **Runtime** | Production-ready images that run as a nonroot user without shells or package managers. |
| **Dev** | Images tagged with `dev` that include shells and package managers for development use. |
| **FIPS** | Images that comply with FIPS 140, STIG, and CIS standards. |

To view available variants, select the **Tags** tab in this repository and then select a tag.

---

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, update your Dockerfile. At minimum, replace the base image. The table below covers this and other common changes:

| Item | Migration note |
|---|---|
| Base image | Replace your base image in the Dockerfile with a Docker Hardened Image. |
| Package management | Non-dev (runtime) images don't include package managers. Use package managers only in `dev`-tagged images. |
| Non-root user | Runtime images run as the `nonroot` user by default. Ensure all required files and directories are accessible to this user. |
| Multi-stage builds | Use `dev`-tagged images for build stages and non-dev images for the runtime stage. Use static images for binary executables. |
| TLS certificates | Docker Hardened Images include standard TLS certificates. No separate installation is needed. |
| Ports | Runtime images run as a nonroot user and cannot bind to privileged ports (below 1024) in Kubernetes or Docker Engine versions older than 20.10. Configure your application to listen on port 1025 or higher. |
| Entrypoint | Docker Hardened Images may have different entrypoints than Docker Official Images. Use `docker inspect` to verify and update your Dockerfile if needed. |
| No shell | Runtime images don't include a shell. Use `dev` images in build stages to run shell commands, then copy artifacts to the runtime stage. |

---

## Troubleshoot migration

### General debugging

Runtime images don't include a shell or debugging tools. Use [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to containers — it provides a shell, common debugging tools, and lets you install additional tools in an ephemeral writable layer that exists only for the duration of the session.

### Permissions

Runtime images run as the `nonroot` user by default. If your application can't access required files or directories, copy them to a different path or update permissions so the `nonroot` user can read them.

### Privileged ports

Runtime images run as a nonroot user and cannot bind to ports below 1024 in Kubernetes or Docker Engine versions older than 20.10. Configure your application to use port 1025 or higher.

### No shell

Runtime images don't include a shell. Use `dev`-tagged images in your build stages to run shell commands, then copy necessary artifacts to the runtime stage. Use Docker Debug to inspect running containers without a shell.

### Entrypoint

Docker Hardened Images may have different entrypoints than Docker Official Images. Run `docker inspect` to check the entrypoint and update your Dockerfile if necessary.
