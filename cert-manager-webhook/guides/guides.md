## Prerequisite

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/<repository>:<tag>`
- Mirrored image: `<your-namespace>/dhi-<repository>:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

### What's included in this cert-manager-webhook image

This Docker Hardened cert-manager-webhook image includes the webhook component of cert-manager in a single,
security-hardened package:

- `cert-manager-webhook`: The webhook binary that uses
  [dynamic admission control](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)
  to validate, mutate, or convert cert-manager resources
- Dynamic admission control support for `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration`
- Conversion webhook support for CRD multi-version API serving
- TLS certificate support for securing communication between the Kubernetes API server and the webhook server

## Start a cert-manager-webhook image

> **Note:** cert-manager-webhook is primarily designed to run inside a Kubernetes cluster as part of a full
> cert-manager deployment. The following standalone Docker command displays the available configuration options.

Run the following command and replace `<tag>` with the image variant you want to run.

```bash
docker run --rm dhi.io/cert-manager-webhook:<tag> --help
```

### Configure TLS

The webhook component is deployed as a pod that runs alongside the cert-manager controller and CA injector
components. In order for the API server to communicate with the webhook component, the webhook requires a TLS
certificate that the apiserver is configured to trust.

The webhook creates `secret/cert-manager-webhook-ca` in the namespace where the webhook is deployed. This secret
contains a self-signed root CA certificate which is used to sign certificates for the webhook pod in order to
fulfill this requirement.

Then the webhook can be configured with either:

- Paths to a TLS certificate and key signed by the webhook CA, or
- A reference to the CA Secret for dynamic generation of the certificate and key on webhook startup

### Command-line flags

The webhook binary accepts configuration via command-line flags. When running via Docker, commonly used flags include:

| Flag                     | Description                                                                      | Default | Required                                                                    |
| ------------------------ | -------------------------------------------------------------------------------- | ------- | --------------------------------------------------------------------------- |
| `--kubeconfig`           | Path inside container to a kubeconfig file used to connect to the target cluster | none    | No (either provide `--kubeconfig` or rely on in-cluster credentials)        |
| `--secure-port`          | Port number the webhook server listens on for HTTPS traffic                      | 10250   | No                                                                          |
| `--tls-cert-file`        | Path to the TLS certificate file for the webhook server                          | none    | Yes (or use CA Secret reference for dynamic generation)                     |
| `--tls-private-key-file` | Path to the TLS private key file for the webhook server                          | none    | Yes (or use CA Secret reference for dynamic generation)                     |
| `-v`, `--v`              | Log level verbosity (number)                                                     | 0       | No                                                                          |

Example:

```bash
# Mount kubeconfig and use --kubeconfig flag
docker run --rm -v ~/.kube/config:/kube/config:ro \
  dhi.io/cert-manager-webhook:<tag> --kubeconfig /kube/config

# Enable verbose logging
docker run --rm dhi.io/cert-manager-webhook:<tag> -v 2
```

## Common cert-manager-webhook use cases

### Validate cert-manager resources

The webhook intercepts CREATE and UPDATE requests for cert-manager resources and validates them against
cert-manager's admission rules before they are persisted to etcd. This prevents misconfigured Certificate,
Issuer, and ClusterIssuer resources from being accepted by the cluster.

The following example shows a `ValidatingWebhookConfiguration` with the webhook configured to validate
cert-manager resources:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: cert-manager-webhook
  annotations:
    cert-manager.io/inject-ca-from-secret: cert-manager/cert-manager-webhook-ca
webhooks:
- name: webhook.cert-manager.io
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail
  clientConfig:
    service:
      name: cert-manager-webhook
      namespace: cert-manager
      path: /validate
    # caBundle populated automatically by cainjector
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["cert-manager.io", "acme.cert-manager.io"]
    apiVersions: ["v1"]
    resources:
    - certificates
    - certificaterequests
    - issuers
    - clusterissuers
    - orders
    - challenges
```

### Mutate cert-manager resources

The webhook can mutate incoming cert-manager resources by setting default values and normalising fields before
they are stored. This ensures consistent resource state across the cluster without requiring every user to
specify every optional field explicitly.

The following example shows a `MutatingWebhookConfiguration` for cert-manager resource defaulting:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: cert-manager-webhook
  annotations:
    cert-manager.io/inject-ca-from-secret: cert-manager/cert-manager-webhook-ca
webhooks:
- name: webhook.cert-manager.io
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail
  clientConfig:
    service:
      name: cert-manager-webhook
      namespace: cert-manager
      path: /mutate
    # caBundle populated automatically by cainjector
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["cert-manager.io"]
    apiVersions: ["v1"]
    resources:
    - certificates
    - certificaterequests
    - issuers
    - clusterissuers
```

### Convert cert-manager resource versions

The webhook handles version conversion for cert-manager CRDs, allowing the Kubernetes API server to store
resources in a single version while serving them across multiple API versions. This is required for cert-manager
CRDs that support multiple API versions simultaneously.

Conversion webhooks are configured directly in the CRD definition:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: certificates.cert-manager.io
spec:
  conversion:
    strategy: Webhook
    webhook:
      conversionReviewVersions: ["v1"]
      clientConfig:
        service:
          name: cert-manager-webhook
          namespace: cert-manager
          path: /convert
        # caBundle populated automatically by cainjector
```

### End-to-end webhook deployment walkthrough

The following steps demonstrate a complete cert-manager-webhook deployment, validated against cert-manager v1.19.4
and `dhi.io/cert-manager-webhook:1-debian13`.

**Prerequisites**: A running Kubernetes cluster with `kubectl` access. The cert-manager CRDs, controller, and
cainjector should be installed and `Ready` before proceeding.

**Step 1: Create the namespace and imagePullSecret**

```bash
kubectl create namespace cert-manager

kubectl create secret docker-registry dhi-pull-secret \
  --docker-server=dhi.io \
  --docker-username=<your-docker-username> \
  --docker-password=<your-docker-password> \
  -n cert-manager
```

**Step 2: Create the ServiceAccount and RBAC**

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cert-manager-webhook
  namespace: cert-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cert-manager-webhook-role
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
- apiGroups: ["admissionregistration.k8s.io"]
  resources:
  - validatingwebhookconfigurations
  - mutatingwebhookconfigurations
  verbs: ["get", "list", "watch", "update"]
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["customresourcedefinitions"]
  verbs: ["get", "list", "watch", "update"]
- apiGroups: ["authorization.k8s.io"]
  resources: ["subjectaccessreviews"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cert-manager-webhook-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cert-manager-webhook-role
subjects:
- kind: ServiceAccount
  name: cert-manager-webhook
  namespace: cert-manager
EOF
```

**Step 3: Deploy cert-manager-webhook**

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-manager-webhook
  namespace: cert-manager
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cert-manager-webhook
  template:
    metadata:
      labels:
        app: cert-manager-webhook
    spec:
      serviceAccountName: cert-manager-webhook
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
      containers:
      - name: cert-manager-webhook
        image: dhi.io/cert-manager-webhook:<tag>
        args:
        - --v=2
        - --secure-port=10250
        - --dynamic-serving-ca-secret-namespace=$(POD_NAMESPACE)
        - --dynamic-serving-ca-secret-name=cert-manager-webhook-ca
        - --dynamic-serving-dns-names=cert-manager-webhook
        - --dynamic-serving-dns-names=cert-manager-webhook.cert-manager
        - --dynamic-serving-dns-names=cert-manager-webhook.cert-manager.svc
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        ports:
        - name: https
          containerPort: 10250
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /livez
            port: 6080
            scheme: HTTP
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /healthz
            port: 6080
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 5
      imagePullSecrets:
      - name: dhi-pull-secret
---
apiVersion: v1
kind: Service
metadata:
  name: cert-manager-webhook
  namespace: cert-manager
spec:
  selector:
    app: cert-manager-webhook
  ports:
  - name: https
    port: 443
    targetPort: 10250
EOF
```

**Step 4: Verify the deployment**

```bash
kubectl get pods -n cert-manager
# NAME                                   READY   STATUS    RESTARTS   AGE
# cert-manager-webhook-xxx               1/1     Running   0          30s

kubectl logs -n cert-manager deployment/cert-manager-webhook | grep -E "Starting|listening|ready"
# I0312 07:10:35  "starting cert-manager webhook" version="1.19.4"
# I0312 07:10:35  "listening for requests" address=":10250"
```

**Step 5: Verify webhook TLS**

Within seconds of startup, the webhook generates its serving certificate from the CA Secret. Verify the CA
Secret was created and inspect the certificate:

```bash
kubectl get secret cert-manager-webhook-ca -n cert-manager
# NAME                       TYPE     DATA   AGE
# cert-manager-webhook-ca    Opaque   3      45s

kubectl get secret cert-manager-webhook-ca -n cert-manager \
  -o jsonpath='{.data.ca\.crt}' | base64 -d \
  | openssl x509 -text -noout | grep -E "Subject:|Not After"
```

**Step 6: Test admission control**

```bash
# Apply a valid Certificate — should succeed
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: cert-manager
spec:
  secretName: test-cert-tls
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
  commonName: test.example.com
  dnsNames:
  - test.example.com
EOF

# Apply an invalid Certificate — should be rejected by the webhook
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: invalid-cert
  namespace: cert-manager
spec:
  secretName: ""
  issuerRef:
    name: ""
EOF
# Expected: Error from server: ... spec.secretName: Required value
```

**Step 7: Clean up**

```bash
kubectl delete certificate test-cert -n cert-manager
kubectl delete deployment cert-manager-webhook -n cert-manager
kubectl delete service cert-manager-webhook -n cert-manager
kubectl delete clusterrolebinding cert-manager-webhook-rolebinding
kubectl delete clusterrole cert-manager-webhook-role
kubectl delete serviceaccount cert-manager-webhook -n cert-manager
kubectl delete secret cert-manager-webhook-ca dhi-pull-secret -n cert-manager
kubectl delete namespace cert-manager
```

## Official images vs Docker Hardened Images

| Feature | DOI (`quay.io/jetstack/cert-manager-webhook`) | DHI (`dhi.io/cert-manager-webhook`) |
|---------|-----------------------------------------------|-------------------------------------|
| **User** | `root` | `nonroot` / UID 65532 (runtime/FIPS) / `root` (dev) |
| **Shell** | Typically included | No (runtime/FIPS) / Yes (dev) |
| **Package manager** | Varies | No (runtime/FIPS) / APT (dev) |
| **Binary path** | `/webhook` | `/usr/local/bin/webhook` |
| **Entrypoint** | `["/webhook"]` | `["/usr/local/bin/webhook"]` |
| **Zero CVE commitment** | No | Yes |
| **FIPS variant** | No | Yes (FIPS + STIG + CIS) |
| **Base OS** | Ubuntu / Debian (no hardening labels) | Docker Hardened Images (Debian 13) |
| **Signed provenance** | No | Yes |
| **SBOM / VEX metadata** | No | Yes |
| **Compliance labels** | None | CIS (runtime), FIPS+STIG+CIS (fips) |
| **ENV: SSL_CERT_FILE** | `/etc/ssl/certs/ca-certificates.crt` | `/etc/ssl/certs/ca-certificates.crt` |
| **Architectures** | amd64, arm64 | amd64, arm64 |

## Image variants

Docker Hardened Images come in different variants depending on their intended use. Image variants are identified by
their tag.

- Runtime variants are designed to run your application in production. These images are intended to be used either
  directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

  - Run as a nonroot user
  - Do not include a shell or a package manager
  - Contain only the minimal set of libraries needed to run the app

- Build-time variants typically include `dev` in the tag name and are intended for use in the first stage of a
  multi-stage Dockerfile. These images typically:

  - Run as the root user
  - Include a shell and package manager
  - Are used to build or compile applications

To view the image variants and get more information about them, select the **Tags** tab for this repository, and then
select a tag.

**Note:** cert-manager consists of multiple components (controller, acmesolver, cainjector, webhook) that work together.
Each component may be available as a separate Docker Hardened Image for deployment flexibility.

### FIPS variants considerations

FIPS variants (`1-fips`, `1-debian13-fips`, `1.19-fips`, `1.19.4-fips`, `1.19.4-debian13-fips`) are available
on Docker Hub and carry CIS, FIPS, and STIG compliance badges with 0 vulnerabilities. Pulling FIPS variants
requires a Docker subscription — the tags return 401 without one.

When using FIPS variants, be aware of the following cert-manager behaviours involving non-FIPS-compliant algorithms:

1. **RFC2136 DNS-01 solver** — The
   [tsigHMACProvider.Generate](https://github.com/cert-manager/cert-manager/blob/master/pkg/issuer/acme/dns/rfc2136/tsig.go#L49)
   function uses SHA1 and MD5 for TSIG authentication, which are forbidden by FIPS and will cause the application
   to panic. To mitigate, specify a FIPS-approved algorithm in your `Issuer` or `ClusterIssuer`:

   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: example-rfc2136
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: admin@example.com
       privateKeySecretRef:
         name: example-account-key
       solvers:
       - dns01:
           rfc2136:
             nameserver: 203.0.113.53:53
             tsigKeyName: example-com-key
             tsigAlgorithm: HMACSHA512
             tsigSecretSecretRef:
               name: tsig-secret
               key: tsig-secret-key
   ```

2. **Legacy TLS cipher suites** (RC4, ChaCha20, SHA1) — cert-manager includes these for compatibility with
   older DNS servers. They are supported but not preferred; modern clients negotiate stronger ciphers automatically.

3. **PKCS#12 legacy profiles** (DES and RC2) — cert-manager supports `LegacyDESPKCS12Profile` and
   `LegacyRC2PKCS12Profile` for backward compatibility. Use the
   [Modern 2023](https://github.com/cert-manager/cert-manager/blob/v1.19.1/pkg/apis/certmanager/v1/types_certificate.go#L536)
   Certificate profile as a FIPS-compliant alternative, or avoid keystores entirely.

4. **CHACHA20_POLY1305 cipher** — If the client supports `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305`, the
   application will panic. Ensure your FIPS-compliant stack does not negotiate this cipher.

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile or Kubernetes manifests. At
minimum, you must update the base image in your existing deployment to a Docker Hardened Image. This and a few other
common changes are listed in the following table of migration notes:

| Item               | Migration note                                                                                                                                                                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Base image         | Replace your base images in your Dockerfile or Kubernetes manifests with a Docker Hardened Image.                                                                                                                                                      |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a dev tag.                                                                                                                              |
| Non-root user      | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user.                                                                                             |
| Multi-stage build  | Utilize images with a dev tag for build stages and non-dev images for runtime. For binary executables, use a static image for runtime.                                                                                                                 |
| TLS certificates   | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates.                                                                                                                                     |
| Ports              | Non-dev hardened images run as a nonroot user by default. cert-manager-webhook listens on port 10250 for HTTPS traffic by default (configurable via `--secure-port`), which works without issues.                                                      |
| Entry point        | Docker Hardened Images may have different entry points than standard cert-manager images. The DHI entry point is `/usr/local/bin/webhook`. Inspect entry points for Docker Hardened Images and update your deployment if necessary.                     |
| No shell           | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage.                                                                            |
| TLS configuration  | The webhook requires a valid TLS certificate and key at startup. Ensure your Deployment mounts the correct certificate files or references the CA Secret for dynamic generation.                                                                       |

The following steps outline the general migration process.

1. **Find hardened images for your app.** The cert-manager-webhook hardened image may have several variants. Inspect
   the image tags and find the image variant that meets your needs. Remember that cert-manager requires multiple
   components to function properly.
1. **Update the image references in your Kubernetes manifests.** Update the image references in your cert-manager
   deployment manifests to use the hardened images. If using Helm, update your values file accordingly.
1. **For custom deployments, update the runtime image in your Dockerfile.** If you're building custom images based on
   cert-manager, ensure that your final image uses the hardened cert-manager-webhook as the base.
1. **Verify component compatibility.** Ensure all cert-manager components (controller, webhook, cainjector, acmesolver)
   are using compatible versions. The webhook works in conjunction with these other components.
1. **Test admission control.** After migration, test that cert-manager resources are correctly validated and mutated,
   and that API server communication with the webhook continues to function correctly.

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

cert-manager-webhook requires read and write access to the `cert-manager-webhook-ca` Secret for TLS certificate
generation, and requires `subjectaccessreviews` permissions for audit logging. Ensure your RBAC configuration grants
appropriate permissions.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to
privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues,
configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on
the host. For example, `docker run -p 443:8443 my-image` will work because the port inside the container is 8443, and
`docker run -p 443:443 my-image` won't work because the port inside the container is 443.

### No shell

By default, image variants intended for runtime don't contain a shell. Use dev images in build stages to run shell
commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers
with no shell.

### Entry point

Docker Hardened Images may have different entry points than standard cert-manager images. Use `docker inspect` to
inspect entry points for Docker Hardened Images and update your Kubernetes deployment if necessary.

### Webhook timeout and connectivity

If the Kubernetes API server cannot reach the webhook within the configured timeout, admission requests will fail or be
allowed depending on the `failurePolicy` setting. Check pod status and logs, and verify the TLS CA Secret exists and is
correctly referenced.

```bash
# Check webhook pod status
kubectl get pods -n cert-manager -l app=cert-manager-webhook

# Check pod logs for TLS or startup errors
kubectl logs -n cert-manager deployment/cert-manager-webhook

# Verify the CA Secret exists
kubectl get secret cert-manager-webhook-ca -n cert-manager
```
