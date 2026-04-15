## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

|                | Example                                          |
| -------------- | ------------------------------------------------ |
| Public image   | `dhi.io/strimzi-operator:<tag>`                  |
| Mirrored image | `<your-namespace>/dhi-strimzi-operator:<tag>`    |

Before pulling images, authenticate to the registry:

```bash
docker login dhi.io
```

### What's included in this image

- Strimzi Cluster Operator binaries for managing Kafka on Kubernetes
- CIS benchmark compliance (runtime variant)
- FIPS 140, STIG, and CIS compliance (FIPS variant)

## Start a strimzi-operator instance

Replace `<tag>` with the image variant you want to run:

```bash
docker run --rm dhi.io/strimzi-operator:<tag> \
  /opt/strimzi/bin/cluster_operator_run.sh --version
```

## Common use cases

### Setup a Kafka Cluster

Use Docker Compose to run the Strimzi Operator alongside a Kafka broker. The operator manages the Kafka cluster
lifecycle based on the configuration provided.

1. Create the `docker-compose.yml`:

   ```yaml
   services:
     strimzi-operator:
       image: dhi.io/strimzi-operator:<tag>
       container_name: strimzi-operator
       environment:
         STRIMZI_NAMESPACE: default
         STRIMZI_FULL_RECONCILIATION_INTERVAL_MS: 120000
         STRIMZI_LOG_LEVEL: INFO
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock

     kafka:
       image: dhi.io/strimzi-kafka:<tag>
       container_name: kafka
       ports:
         - "9092:9092"
       environment:
         KAFKA_NODE_ID: 1
         KAFKA_PROCESS_ROLES: broker,controller
         KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
         KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
         KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
         KAFKA_CONTROLLER_QUORUM_VOTERS: 1@localhost:9093
         KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
       command:
         - /bin/bash
         - -c
         - |
           /opt/kafka/bin/kafka-storage.sh format \
             --config /opt/kafka/config/server.properties \
             --cluster-id $(cat /proc/sys/kernel/random/uuid | tr -d '-') && \
           /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
       depends_on:
         - strimzi-operator
   ```

2. Start the services:

   ```bash
   docker compose up -d
   docker compose logs strimzi-operator
   ```

3. Verify the broker is reachable and create a test topic:

   ```bash
   docker exec kafka /opt/kafka/bin/kafka-topics.sh \
     --bootstrap-server localhost:9092 \
     --create --topic my-topic \
     --partitions 3 --replication-factor 1

   docker exec kafka /opt/kafka/bin/kafka-topics.sh \
     --bootstrap-server localhost:9092 \
     --list
   ```

---

### Kafka Cluster Monitoring

Expose JMX metrics from the Kafka broker managed by the Strimzi Operator for scraping by Prometheus.

1. Update `docker-compose.yml` to expose the metrics port:

   ```yaml
   services:
     strimzi-operator:
       image: dhi.io/strimzi-operator:<tag>
       container_name: strimzi-operator
       environment:
         STRIMZI_NAMESPACE: default
         STRIMZI_FULL_RECONCILIATION_INTERVAL_MS: 120000
         STRIMZI_LOG_LEVEL: INFO
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock

     kafka:
       image: dhi.io/strimzi-kafka:<tag>
       container_name: kafka
       ports:
         - "9092:9092"
         - "9404:9404"
       environment:
         KAFKA_NODE_ID: 1
         KAFKA_PROCESS_ROLES: broker,controller
         KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
         KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
         KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
         KAFKA_CONTROLLER_QUORUM_VOTERS: 1@localhost:9093
         KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
         KAFKA_JMX_PORT: 9999
         KAFKA_JMX_HOSTNAME: localhost
       command:
         - /bin/bash
         - -c
         - |
           /opt/kafka/bin/kafka-storage.sh format \
             --config /opt/kafka/config/server.properties \
             --cluster-id $(cat /proc/sys/kernel/random/uuid | tr -d '-') && \
           /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
       depends_on:
         - strimzi-operator
   ```

2. Start and verify metrics are available:

   ```bash
   docker compose up -d
   curl http://localhost:9404/metrics | grep kafka_server
   ```

---

## Docker Official Image vs Docker Hardened Image

| Feature             | DOI (`quay.io/strimzi/operator`) | DHI (`dhi.io/strimzi-operator`)     |
| ------------------- | -------------------------------- | ----------------------------------- |
| Base OS             | UBI 8 (Red Hat)                  | Debian 13                           |
| User                | 1001                             | `strimzi` (UID 1001)                |
| Zero CVE commitment | No                               | Yes                                 |
| FIPS variant        | No                               | Yes (FIPS + STIG + CIS)             |
| Architectures       | amd64                            | amd64, arm64                        |

## Migrate to a Docker Hardened Image

| Item               | Migration note                                                                                                                                                                                                                   |
| :----------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------    |
| Base image         | Replace your base image in the Dockerfile with a Docker Hardened Image.                                                                                                                                                          |
| Package management | Non-dev (runtime) images don't include package managers. Use package managers only in `dev`-tagged images.                                                                                                                       |
| Non-root user      | Runtime images run as the `strimzi` user (UID 1001) by default. Ensure all required files and directories are accessible to this user.                                                                                           |
| Multi-stage builds | Use `dev`-tagged images for build stages and non-dev images for the runtime stage.                                                                                                                                               |
| TLS certificates   | Docker Hardened Images include standard TLS certificates. No separate installation is needed.                                                                                                                                    |
| Ports              | Runtime images run as a nonroot user and cannot bind to privileged ports (below 1024) in Kubernetes or Docker Engine versions older than 20.10. Configure your application to listen on port 1025 or higher.                     |
| Entrypoint         | No entrypoint is set — pass the full binary path explicitly (e.g., `/opt/strimzi/bin/cluster_operator_run.sh`). Always supply an explicit `command` in Compose or Kubernetes manifests, otherwise the container exits immediately.|

## Troubleshoot migration

### General debugging

Runtime images don't include a shell or debugging tools. Use
[Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to containers — it provides a shell,
common debugging tools, and lets you install additional tools in an ephemeral writable layer that exists only for the
duration of the session.

### Permissions

Runtime images run as the `strimzi` user (UID 1001) by default. If the operator can't access required files or
directories, copy them to a different path or update permissions so the `strimzi` user can read them.

### Privileged ports

Runtime images run as a nonroot user and cannot bind to ports below 1024 in Kubernetes or Docker Engine versions older
than 20.10. Configure your application to use port 1025 or higher.

### Entrypoint

No entrypoint is set on this image. Run `docker inspect` to verify and always pass the full binary path explicitly in
your `command`.
