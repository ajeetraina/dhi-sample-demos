# ClickHouse Metrics Exporter

## Prerequisites

Before you can use any Docker Hardened Image, you must mirror the image 
repository from the catalog to your organization. To mirror the repository, 
select either **Mirror to repository** or 
**View in repository > Mirror to repository**, and then follow the 
on-screen instructions.

### Required Image Repositories

The ClickHouse Metrics Exporter requires three Docker Hardened Image repositories to be mirrored to your organization:

1. **ClickHouse Operator** - `dhi-clickhouse-operator`
   - Required to manage ClickHouse clusters in Kubernetes
   - Mirror version 0.25.6 or later

2. **ClickHouse Server** - `dhi-clickhouse-server`
   - Required to run ClickHouse database instances
   - Mirror version 25 or later

3. **ClickHouse Metrics Exporter** - `dhi-clickhouse-metrics-exporter`
   - The metrics exporter itself
   - Mirror version 0.25.6 or later

**Important:** You cannot pull these images directly from `dockerdevrel`. They must be mirrored to your organization's namespace first. All three repositories must be mirrored before proceeding with deployment.

After mirroring, replace `<your-namespace>` in all examples below with your organization's namespace (e.g., `mycompany` if you mirrored to `mycompany/dhi-clickhouse-operator`).

## Start a ClickHouse Metrics Exporter instance

The ClickHouse Metrics Exporter is designed to work as part of the ClickHouse Operator in Kubernetes. It automatically discovers and monitors ClickHouse clusters managed by the ClickHouse Operator, providing comprehensive operational metrics through a standard `/metrics` endpoint for Prometheus scraping.

This image cannot run as a standalone container outside of Kubernetes as it requires access to the Kubernetes API and ClickHouseInstallation custom resources.

### Deploy ClickHouse Operator (DHI)

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

### Deploy Metrics Exporter (DHI)

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

### Available tags

- `0` or `0-debian13` - Latest version 0.x series with Debian 13 base
- `0.25` or `0.25-debian13` - Version 0.25.x with Debian 13 base
- `0.25.6` or `0.25.6-debian13` - Specific version 0.25.6 with Debian 13 base

All variants support both `linux/amd64` and `linux/arm64` architectures.

### Related Docker Hardened Images

The ClickHouse Metrics Exporter works with other ClickHouse Docker Hardened Images:

- **ClickHouse Operator**: `dhi-clickhouse-operator:0.25.6` (runtime) or `dhi-clickhouse-operator:0.25.6-dev` (build-time)
- **ClickHouse Server**: `dhi-clickhouse-server:25` (see ClickHouse Server DHI guide for details)

## Migrate to a Docker Hardened Image

To migrate your ClickHouse Operator deployment to use the Docker Hardened Images, you must update your Kubernetes manifests. At minimum, you must update the image references in your existing deployments to Docker Hardened Images. This and a few other common changes are listed in the following table of migration notes:

| Item | Migration note |
|------|----------------|
| Base image | Replace the metrics exporter image in your ClickHouse Operator deployment with the Docker Hardened Image. |
| Operator image | Replace the ClickHouse Operator image with `dhi-clickhouse-operator:0.25.6`. |
| ClickHouse image | Replace ClickHouse server images in ClickHouseInstallation specs with `dhi-clickhouse-server:25`. |
| Non-root user | By default, the image runs as the nonroot user. Ensure that mounted volumes and service account permissions are accessible to the nonroot user. |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| Ports | The hardened image runs as a nonroot user by default. The metrics port 8888 works without issues as it's above 1024. |
| Entry point | The exporter binary is located at `/usr/local/bin/clickhouse-metrics-exporter`. Docker Hardened Images may have different entry points than standard images. |
| ServiceAccount | The deployment must use a ServiceAccount with appropriate RBAC permissions to access ClickHouseInstallation resources. |
| Namespace | Deploy in the same namespace as the ClickHouse Operator's ServiceAccount (typically `kube-system`). |

The following steps outline the general migration process:

1. **Find hardened images for your deployment.**
    
    A hardened image may have several variants. Inspect the image tags and 
    find the image variant that meets your needs. ClickHouse Metrics Exporter images are available in version 0.25.6 with Debian 13 base. You'll also need `dhi-clickhouse-operator:0.25.6` and `dhi-clickhouse-server:25`.
    
2. **Update the image in your Kubernetes manifests.**
    
    Update the `image` field in your Deployment for the ClickHouse Operator and metrics exporter to reference the hardened images. Update ClickHouseInstallation specs to use `dhi-clickhouse-server:25`.
    
3. **Verify RBAC permissions.**
    
    Ensure that the ServiceAccount has appropriate RBAC permissions to access ClickHouseInstallation resources and the Kubernetes API.

4. **Configure ClickHouse authentication.**
    
    Ensure the `clickhouse_operator` user exists in your ClickHouse clusters with appropriate permissions to query system tables for metrics.

5. **Test in a non-production environment.**
    
    Deploy the updated manifest to a test namespace and verify metrics are being collected correctly before rolling out to production.

## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools 
for debugging. The recommended method for debugging applications built with 
Docker Hardened Images is to use Kubernetes-native debugging tools or
[Docker Debug](https://docs.docker.com/engine/reference/commandline/debug/).

For Kubernetes debugging:

```bash
# Check pod logs
kubectl logs -n kube-system -l app=clickhouse-operator-metrics

# Describe the pod for events
kubectl describe pod -n kube-system <pod-name>

# Use kubectl debug to attach a debug container
kubectl debug -n kube-system pod/<pod-name> -it --image=busybox --target=metrics-exporter
```

### Permissions

By default, the image runs as the nonroot user. Ensure that:
- The ServiceAccount has proper RBAC permissions to list and watch ClickHouseInstallation resources
- Any mounted ConfigMaps or Secrets are readable by the nonroot user
- The ServiceAccount exists in the deployment namespace

### Privileged ports

The hardened image runs as a nonroot user by default. The default metrics endpoint port (8888) is above 1024 and works without issues.

### No shell

By default, the runtime image doesn't contain a shell. For debugging:
- Use `kubectl logs` to view container logs
- Use `kubectl describe` to view pod events
- Use `kubectl debug` to attach a debugging container with tools
- Use Docker Debug if you have access to the node

### Entry point

The metrics exporter binary is located at `/usr/local/bin/clickhouse-metrics-exporter`. You can override the entry point in your Kubernetes deployment if needed, but this is rarely necessary.

### ServiceAccount not found

If you see an error about the ServiceAccount not being found:

```
error looking up service account clickhouse-system/clickhouse-operator: 
serviceaccount "clickhouse-operator" not found
```

This occurs when the metrics exporter deployment is in a different namespace than the ClickHouse Operator's ServiceAccount. Deploy the metrics exporter in the same namespace as the operator (typically `kube-system`).

### ClickHouse authentication errors

If metrics show authentication failures in the logs:

```
Authentication failed: password is incorrect, or there is no user with such name
```

Configure the `clickhouse_operator` user in your ClickHouseInstallation:

```yaml
configuration:
  users:
    clickhouse_operator/password: your-secure-password
    clickhouse_operator/networks/ip:
      - "0.0.0.0/0"
    clickhouse_operator/profile: default
```

### Kubernetes API connection issues

If the exporter fails to connect to the Kubernetes API:

1. Verify the ServiceAccount has appropriate RBAC permissions:
   ```bash
   kubectl auth can-i list clickhouseinstallations.clickhouse.altinity.com \
     --as=system:serviceaccount:kube-system:clickhouse-operator
   ```

2. Check if the kubeconfig is correctly mounted (if running outside cluster)

3. Verify network connectivity to the Kubernetes API server

4. Check logs for specific error messages:
   ```bash
   kubectl logs -n kube-system -l app=clickhouse-operator-metrics
   ```

### ImagePullBackOff or pull access denied

If you see errors like:

```
Failed to pull image: pull access denied, repository does not exist or may require authorization
ImagePullBackOff
```

This means the Docker Hardened Image repositories have not been mirrored to your organization. You cannot pull DHI images directly from `dockerdevrel`.

**Solution:**

1. Go to the Docker Hardened Images catalog
2. Mirror all three required repositories to your organization:
   - `dhi-clickhouse-operator`
   - `dhi-clickhouse-server`
   - `dhi-clickhouse-metrics-exporter`
3. Update all image references in your manifests to use your organization's namespace
4. Redeploy with the corrected image references

**To verify your mirrored images:**

```bash
# Check if you can pull from your organization
docker pull <your-namespace>/dhi-clickhouse-operator:0.25.6
docker pull <your-namespace>/dhi-clickhouse-server:25
docker pull <your-namespace>/dhi-clickhouse-metrics-exporter:0.25.6
```

### ClickHouseInstallation status shows "Aborted"

If the ClickHouseInstallation shows a status of "Aborted" with errors like:

```
FAILED to reconcile CR clickhouse-system/test-cluster, err: crud error - should abort
reconcile completed UNSUCCESSFULLY
```

The operator's reconciliation process may have timed out before the ClickHouse Server completed initialization. Docker Hardened Images may take longer to start due to security hardening measures.

**Solutions:**

1. Increase probe delays in the ClickHouseInstallation pod template:
   ```yaml
   templates:
     podTemplates:
       - name: clickhouse-stable
         spec:
           containers:
             - name: clickhouse
               image: <your-namespace>/dhi-clickhouse-server:25
               livenessProbe:
                 httpGet:
                   path: /ping
                   port: 8123
                 initialDelaySeconds: 180
                 periodSeconds: 10
                 failureThreshold: 10
               readinessProbe:
                 httpGet:
                   path: /ping
                   port: 8123
                 initialDelaySeconds: 120
                 periodSeconds: 5
                 failureThreshold: 10
   ```

2. Ensure sufficient cluster resources for faster container startup

3. Consider using standard ClickHouse images if startup time is critical for your deployment

4. Check operator logs for specific timeout details:
   ```bash
   kubectl logs -n kube-system -l app=clickhouse-operator --tail=50
   ```

The metrics exporter DHI works correctly once a stable ClickHouse cluster is established.
