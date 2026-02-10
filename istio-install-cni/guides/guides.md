## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/<repository>:<tag>`
- Mirrored image: `<your-namespace>/dhi-<repository>:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

## What's included in this Istio CNI image

This Docker Hardened Istio CNI image includes:

- Istio CNI plugin binary for pod network configuration
- CNI configuration management for chaining with existing CNI plugins
- iptables rules management for traffic redirection in sidecar mode
- Ambient mesh networking support for ztunnel integration
- tini as the init process for proper signal handling

## Start an Istio CNI image

First follow the
[authentication instructions for DHI in Kubernetes](https://docs.docker.com/dhi/how-to/k8s/#authentication).

The Istio CNI image runs as a **DaemonSet** on each node in your Kubernetes cluster. It installs the CNI plugin binary
and manages pod network namespace configuration. This image cannot be run standalone.

### Basic usage

Replace `<secret name>` with your Kubernetes image pull secret and `<tag>` with the image variant you want to use.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: istio-cni-node
  namespace: istio-system
spec:
  selector:
    matchLabels:
      k8s-app: istio-cni-node
  template:
    metadata:
      labels:
        k8s-app: istio-cni-node
    spec:
      hostNetwork: true
      imagePullSecrets:
      - name: <secret name>
      containers:
      - name: install-cni
        image: dhi.io/istio-install-cni:<tag>
        securityContext:
          privileged: true
```

### With istioctl (recommended)

Use `istioctl` to install Istio with the hardened CNI image:

```bash
$ istioctl install --set components.cni.enabled=true \
  --set values.cni.image=dhi.io/istio-install-cni:<tag> \
  --set values.cni.imagePullSecrets[0]=<secret name>
```

### With Helm

```bash
$ helm install istio-cni istio/cni -n istio-system \
  --set cni.image=dhi.io/istio-install-cni \
  --set cni.tag=<tag> \
  --set global.imagePullSecrets[0]=<secret name>
```

## Configuration options

The Istio CNI image supports configuration through environment variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `CNI_NET_DIR` | Directory for CNI network configuration | `/etc/cni/net.d` | No |
| `CNI_BIN_DIR` | Directory for CNI plugin binaries | `/opt/cni/bin` | No |
| `CNI_NETWORK_CONFIG` | CNI plugin configuration JSON | (auto-generated) | No |
| `CNI_CONF_NAME` | Name of the CNI configuration file | (auto) | No |
| `CHAINED_CNI_PLUGIN` | Whether to chain with existing CNI plugins | `true` | No |
| `KUBECFG_FILE_NAME` | Kubeconfig file name for API server access | `ZZZ-istio-cni-kubeconfig` | No |
| `LOG_LEVEL` | Logging verbosity level | `info` | No |
| `AMBIENT_ENABLED` | Enable ambient mesh support | `false` | No |

Example with custom configuration:

```yaml
containers:
- name: install-cni
  image: dhi.io/istio-install-cni:<tag>
  env:
  - name: LOG_LEVEL
    value: "debug"
  - name: AMBIENT_ENABLED
    value: "true"
  securityContext:
    privileged: true
```

## Common Istio CNI use cases

### Sidecar mode networking

The CNI plugin configures iptables rules for traffic redirection when pods with Istio sidecars are scheduled,
eliminating the need for privileged init containers.

Deploy the DaemonSet and enable sidecar injection:

```bash
# Apply the CNI DaemonSet
$ kubectl apply -f istio-cni-daemonset.yaml

# Verify the CNI pods are running on each node
$ kubectl get pods -n istio-system -l k8s-app=istio-cni-node
NAME                   READY   STATUS    RESTARTS   AGE
istio-cni-node-abc12   1/1     Running   0          30s
istio-cni-node-def34   1/1     Running   0          30s

# Enable sidecar injection for your namespace
$ kubectl label namespace default istio-injection=enabled

# Deploy a sample workload
$ kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/bookinfo/platform/kube/bookinfo.yaml

# Verify no privileged init containers are used
$ kubectl describe pod -l app=productpage | grep -A2 "Init Containers"
```

### Ambient mesh networking

In ambient mode, the CNI plugin monitors pods and configures networking for the ambient mesh without sidecar injection.

```bash
# Install with ambient mode enabled
$ istioctl install --set profile=ambient \
  --set values.cni.image=dhi.io/istio-install-cni:<tag>

# Label a namespace for ambient mesh
$ kubectl label namespace default istio.io/dataplane-mode=ambient

# Verify CNI is handling ambient networking
$ kubectl logs -n istio-system -l k8s-app=istio-cni-node | grep ambient
```

### Jenkins or CI/CD pipeline integration

When running Istio in CI/CD test clusters (for example, with Kind or Minikube), configure the CNI for testing:

```bash
# Create a Kind cluster with CNI support
$ kind create cluster --config kind-config.yaml

# Install Istio with DHI CNI image
$ istioctl install --set components.cni.enabled=true \
  --set values.cni.image=dhi.io/istio-install-cni:<tag> \
  --set values.cni.cniBinDir=/opt/cni/bin \
  --set values.cni.cniConfDir=/etc/cni/net.d
```

## Official Docker image (DOI) vs Docker Hardened Image (DHI)

Key differences specific to the Istio CNI DHI:

| Feature | DOI (`istio/install-cni`) | DHI (`dhi.io/istio-install-cni`) |
|---------|--------------------------|----------------------------------|
| User | root | nonroot (runtime) / root (dev) |
| Shell | Yes | No (runtime) / Yes (dev) |
| Package manager | Yes (apt) | No (runtime) / Yes (dev) |
| SBOM | No | Yes |
| FIPS variant | No | Yes |
| Zero CVE commitment | No | Yes |
| Base OS | Ubuntu | Docker Hardened Images (Debian 13) |
| Privileged requirement | Yes | Yes (required for CNI operations) |

## Image variants

Docker Hardened Images come in different variants depending on their intended use. Image variants are identified by
their tag.

**Runtime variants** are designed for production use and run the CNI plugin as a privileged container. These images
typically:

- Run as a nonroot user
- Do not include a shell or a package manager
- Contain only the minimal set of libraries needed to run the CNI plugin

**Build-time variants** typically include `dev` in the tag name and are intended for debugging and development. These
images typically:

- Run as the root user
- Include a shell and package manager
- Are useful for troubleshooting CNI issues on nodes

**FIPS variants** include `fips` in the variant name and tag. They come in both runtime and build-time variants. These
variants use cryptographic modules that have been validated under FIPS 140, a U.S. government standard for secure
cryptographic operations. Use FIPS variants in regulated environments (FedRAMP, government, financial services).

The Istio CNI Docker Hardened Image is available in all variant types: runtime, dev, FIPS, and FIPS-dev. To view the
image variants and get more information about them, select the **Tags** tab for this repository.

## Migrate to a Docker Hardened Image

To migrate your Istio CNI deployment to a Docker Hardened Image, update your installation configuration. The following
table lists common migration considerations.

| Item | Migration note |
|------|---------------|
| Base image | Replace `docker.io/istio/install-cni` with `dhi.io/istio-install-cni` in your DaemonSet, Helm values, or istioctl configuration. |
| Privileged context | The DHI still requires `privileged: true` security context for CNI operations. |
| Non-root user | By default, runtime images run as the nonroot user. The CNI binary handles privilege escalation internally. |
| RBAC permissions | Ensure the DaemonSet ServiceAccount has appropriate ClusterRole bindings for pod monitoring and CNI configuration. |
| FIPS compliance | If your environment requires FIPS 140 validated cryptography, use tags with `-fips` suffix. |
| Image pull secrets | Configure Kubernetes image pull secrets for the DHI registry. See the [authentication instructions](https://docs.docker.com/dhi/how-to/k8s/#authentication). |
| Entry point | Docker Hardened Images may have different entry points. Use `docker inspect` to verify the entrypoint matches your configuration. |
| No shell | Runtime images don't contain a shell. Use `dev` images or Docker Debug for troubleshooting. |

The following steps outline the general migration process.

1. **Find hardened images for your deployment.**

   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.
   For production, use a runtime variant. For debugging, use a `dev` variant.

2. **Update your installation configuration.**

   Update the Istio CNI image reference in your DaemonSet manifest, Helm values, or istioctl install flags:

   ```yaml
   image: dhi.io/istio-install-cni:<tag>
   ```

3. **Configure image pull authentication.**

   Create a Kubernetes secret for the DHI registry:

   ```bash
   $ kubectl create secret docker-registry dhi-pull-secret \
     --docker-server=dhi.io \
     --docker-username=<username> \
     --docker-password=<password> \
     -n istio-system
   ```

4. **Verify RBAC permissions.**

   Ensure the CNI DaemonSet ServiceAccount has the required permissions:

   ```bash
   $ kubectl get clusterrolebinding | grep istio-cni
   ```

5. **Validate the deployment.**

   After migration, verify the CNI pods are running and functioning:

   ```bash
   $ kubectl get daemonset -n istio-system istio-cni-node
   $ kubectl logs -n istio-system -l k8s-app=istio-cni-node --tail=20
   ```

## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for
debugging applications built with Docker Hardened Images is to use
[Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to these containers. Docker Debug provides
a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists
during the debugging session.

### Permissions

By default image variants intended for runtime, run as a nonroot user. Ensure that necessary files and directories are
accessible to that user. You may need to copy files to different directories or change permissions so your application
running as a nonroot user can access them.

To view the user for an image variant, select the **Tags** tab for this repository.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to
privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues,
configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on
the host. For example, `docker run -p 80:8080 my-image` will work because the port inside the container is 8080, and
`docker run -p 80:81 my-image` won't work because the port inside the container is 81.

> **Note:** The Istio CNI DaemonSet typically runs with `privileged: true` and `hostNetwork: true`, which may override
> nonroot port restrictions. This note applies primarily if you customize the security context.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev` images in build stages to run shell
commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers
with no shell.

To see if a shell is available in an image variant and which one, select the **Tags** tab for this repository.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images.

To view the Entrypoint or CMD defined for an image variant, select the **Tags** tab for this repository, select a tag,
and then select the **Specifications** tab.
