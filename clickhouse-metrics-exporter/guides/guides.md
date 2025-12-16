# ClickHouse Metrics Exporter

## Prerequisites

Before you can use any Docker Hardened Image, you must mirror the following image 
repositories from the catalog (`dhi-clickhouse-operator`, `dhi-clickhouse-server` and `dhi-clickhouse-metrics-exporter`) to your organization. To mirror the repository, 
select either **Mirror to repository** or 
**View in repository > Mirror to repository**, and then follow the 
on-screen instructions.


## Start a ClickHouse Metrics Exporter instance

The ClickHouse Metrics Exporter is designed to work as part of the ClickHouse Operator in Kubernetes. It automatically discovers and monitors ClickHouse clusters managed by the ClickHouse Operator, providing comprehensive operational metrics through a standard `/metrics` endpoint for Prometheus scraping.

This image cannot run as a standalone container outside of Kubernetes as it requires access to the Kubernetes API and ClickHouseInstallation custom resources.

### Deploy ClickHouse Operator 

First, deploy the ClickHouse Operator using the Docker Hardened Image. Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: clickhouse-operator
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: clickhouse-operator
rules:
- apiGroups:
  - clickhouse.altinity.com
  resources:
  - clickhouseinstallations
  - clickhouseinstallationtemplates
  - clickhouseoperatorconfigurations
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
- apiGroups:
  - ""
  resources:
  - configmaps
  - services
  - persistentvolumeclaims
  - secrets
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
- apiGroups:
  - apps
  resources:
  - statefulsets
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: clickhouse-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: clickhouse-operator
subjects:
- kind: ServiceAccount
  name: clickhouse-operator
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clickhouse-operator
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clickhouse-operator
  template:
    metadata:
      labels:
        app: clickhouse-operator
    spec:
      serviceAccountName: clickhouse-operator
      containers:
      - name: clickhouse-operator
        image: <your-namespace>/dhi-clickhouse-operator:<tag>
        imagePullPolicy: Always
        env:
        - name: OPERATOR_POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: OPERATOR_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
```

### Deploy Metrics Exporter 

Deploy the metrics exporter using the Docker Hardened Image. Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clickhouse-operator-metrics
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clickhouse-operator-metrics
  template:
    metadata:
      labels:
        app: clickhouse-operator-metrics
    spec:
      serviceAccountName: clickhouse-operator
      containers:
      - name: metrics-exporter
        image: <your-namespace>/dhi-clickhouse-metrics-exporter:<tag>
        ports:
        - name: metrics
          containerPort: 8888
        args:
        - "-metrics-endpoint=:8888"
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: clickhouse-operator-metrics
  namespace: kube-system
spec:
  ports:
  - name: metrics
    port: 8888
    targetPort: 8888
  selector:
    app: clickhouse-operator-metrics
```

### Deploy a ClickHouse Cluster (DHI)

Deploy a ClickHouse cluster using the Docker Hardened Image for the metrics exporter to monitor. Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```yaml
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: my-cluster
  namespace: clickhouse-system
spec:
  configuration:
    users:
      clickhouse_operator/password: your-secure-password
      clickhouse_operator/networks/ip:
        - "0.0.0.0/0"
      clickhouse_operator/profile: default
    clusters:
      - name: production
        layout:
          shardsCount: 1
          replicasCount: 1
  templates:
    podTemplates:
      - name: clickhouse-stable
        spec:
          containers:
            - name: clickhouse
              image: <your-namespace>/dhi-clickhouse-server:<tag>
```

Verify the deployment:

```bash
kubectl get pods -n kube-system -l app=clickhouse-operator-metrics
kubectl logs -n kube-system -l app=clickhouse-operator-metrics
```

## Common ClickHouse Metrics Exporter use cases

### Integrate with Prometheus using ServiceMonitor

Create a ServiceMonitor for Prometheus Operator to automatically scrape metrics from the exporter.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: clickhouse-operator-metrics
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: clickhouse-operator-metrics
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### Configure ClickHouse authentication

Configure the `clickhouse_operator` user in your ClickHouseInstallation to allow the exporter to query ClickHouse metrics. Ensure you're using the Docker Hardened ClickHouse Server image.

```yaml
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: my-cluster
  namespace: clickhouse-system
spec:
  configuration:
    users:
      clickhouse_operator/password: your-secure-password
      clickhouse_operator/networks/ip:
        - "0.0.0.0/0"
      clickhouse_operator/profile: default
    clusters:
      - name: production
        layout:
          shardsCount: 2
          replicasCount: 2
  templates:
    podTemplates:
      - name: clickhouse-stable
        spec:
          containers:
            - name: clickhouse
              image: <your-namespace>/dhi-clickhouse-server:<tag>
```

### Mount custom configuration

Mount a custom ClickHouse Operator configuration file to modify exporter behavior.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: clickhouse-operator-config
  namespace: kube-system
data:
  config.yaml: |
    clickhouse:
      configuration:
        users:
          default/networks/ip: "::/0"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clickhouse-operator-metrics
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: metrics-exporter
        image: <your-namespace>/dhi-clickhouse-metrics-exporter:<tag>
        args:
        - "-metrics-endpoint=:8888"
        - "-config=/etc/clickhouse-operator/config.yaml"
        volumeMounts:
        - name: config
          mountPath: /etc/clickhouse-operator
      volumes:
      - name: config
        configMap:
          name: clickhouse-operator-config
```

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Standard ClickHouse Metrics Exporter | Docker Hardened ClickHouse Metrics Exporter |
|---------|--------------------------------------|---------------------------------------------|
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | No shell in runtime variants |
| Package manager | apt available | No package manager in runtime variants |
| User | May run as root | Runs as nonroot user |
| Attack surface | Larger due to additional utilities | Minimal, only essential components |
| Debugging | Traditional shell debugging | Use Docker Debug or kubectl debug for troubleshooting |

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
- Kubernetes-specific debugging with `kubectl debug`

Docker Debug provides a shell, common debugging tools, and lets you
install other tools in an ephemeral, writable layer that only exists during the
debugging session.

For Kubernetes environments, you can use kubectl debug:

```bash
kubectl debug -n kube-system pod/<pod-name> -it --image=busybox --target=metrics-exporter
```

Or use Docker Debug if you have access to the node:

```bash
docker debug <container-id>
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

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the following table of migration notes:

| Item | Migration note |
|------|----------------|
| Base image | Replace your base images in your Dockerfile with a Docker Hardened Image. |
| Non-root user | By default, images run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| Ports | Hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. ClickHouse default ports 8123 and 9000 work without issues. |
| Entry point | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| ulimits | Always set `--ulimit nofile=262144:262144` for proper ClickHouse operation. |

The following steps outline the general migration process.

1. **Find hardened images for your app.**
    
    A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs. ClickHouse images are available in multiple versions (25.3, 25.8, 25.11) with Debian 13 base.

2. **Update the base image in your Dockerfile.**
    
    Update the base image in your application's Dockerfile to the hardened image you found in the previous step.

3. **Verify permissions**
    
    Since the image runs as nonroot user, ensure that data directories and mounted volumes are accessible to the nonroot user.

## Troubleshoot migration

### General debugging

The recommended method for debugging applications built with Docker Hardened Images is to use [Docker Debug](https://docs.docker.com/engine/reference/commandline/debug/) to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Permissions

By default image variants run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so your application running as the nonroot user can access them.

### Privileged ports

Hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.

