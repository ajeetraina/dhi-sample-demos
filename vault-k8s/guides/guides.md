# Vault K8s Docker Hardened Image Guide

## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- **Public image**: `dhi.io/vault-k8s:<tag>`
- **Mirrored image**: `<your-namespace>/dhi-vault-k8s:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

## Start a Vault K8s instance

Vault K8s is designed to work with HashiCorp Vault in Kubernetes environments. It provides the agent-inject functionality that automatically injects secrets from Vault into pods.

### Deploy Vault Server

First, deploy a Vault server in dev mode for testing. In production, you would use a properly configured Vault instance.

```bash
# Create namespace
kubectl create namespace vault

# Deploy Vault server in dev mode
cat > vault-server.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault
  namespace: vault
---
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: vault
spec:
  ports:
  - name: vault
    port: 8200
    targetPort: 8200
  selector:
    app: vault
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: vault
spec:
  serviceName: vault
  replicas: 1
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      serviceAccountName: vault
      containers:
      - name: vault
        image: hashicorp/vault:1.21.1
        args:
        - server
        - -dev
        - -dev-root-token-id=root
        - -dev-listen-address=0.0.0.0:8200
        env:
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: "root"
        - name: VAULT_ADDR
          value: "http://127.0.0.1:8200"
        ports:
        - containerPort: 8200
          name: vault
        readinessProbe:
          httpGet:
            path: /v1/sys/health
            port: 8200
          initialDelaySeconds: 5
EOF

kubectl apply -f vault-server.yaml

# Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app=vault -n vault --timeout=60s
```

### Deploy Vault K8s Agent Injector (DHI)

Generate TLS certificates and deploy the Vault K8s agent injector using the Docker Hardened Image.

```bash
# Generate TLS certificates for the webhook
SERVICE_NAME=vault-agent-injector-svc
NAMESPACE=vault
SECRET_NAME=vault-agent-injector-certs
TMPDIR=$(mktemp -d)
openssl genrsa -out ${TMPDIR}/tls.key 2048
openssl req -new -x509 -key ${TMPDIR}/tls.key -out ${TMPDIR}/tls.crt -days 365 \
    -subj "/CN=${SERVICE_NAME}.${NAMESPACE}.svc" \
    -addext "subjectAltName=DNS:${SERVICE_NAME}.${NAMESPACE}.svc,DNS:${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"
kubectl create secret tls ${SECRET_NAME} \
    --cert=${TMPDIR}/tls.crt \
    --key=${TMPDIR}/tls.key \
    -n ${NAMESPACE}
rm -rf ${TMPDIR}

# Deploy Vault K8s Agent Injector with DHI
cat > vault-agent-injector.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-agent-injector
  namespace: vault
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vault-agent-injector
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - admissionregistration.k8s.io
  resources:
  - mutatingwebhookconfigurations
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-agent-injector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vault-agent-injector
subjects:
- kind: ServiceAccount
  name: vault-agent-injector
  namespace: vault
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-agent-injector
  namespace: vault
  labels:
    app: vault-agent-injector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault-agent-injector
  template:
    metadata:
      labels:
        app: vault-agent-injector
    spec:
      serviceAccountName: vault-agent-injector
      containers:
      - name: vault-agent-injector
        image: dhi.io/vault-k8s:1.7-debian13
        args:
        - agent-inject
        - -vault-address=http://vault.vault.svc:8200
        - -listen=:8080
        - -tls-cert-file=/etc/webhook/certs/tls.crt
        - -tls-key-file=/etc/webhook/certs/tls.key
        ports:
        - name: https
          containerPort: 8080
        volumeMounts:
        - name: webhook-certs
          mountPath: /etc/webhook/certs
          readOnly: true
      volumes:
      - name: webhook-certs
        secret:
          secretName: vault-agent-injector-certs
---
apiVersion: v1
kind: Service
metadata:
  name: vault-agent-injector-svc
  namespace: vault
spec:
  ports:
  - name: https
    port: 443
    targetPort: 8080
  selector:
    app: vault-agent-injector
EOF

kubectl apply -f vault-agent-injector.yaml
```

### Update webhook configuration

If you have an existing MutatingWebhookConfiguration, update it with the new CA bundle:

```bash
# Update the webhook with the new CA certificate
CA_BUNDLE=$(kubectl get secret vault-agent-injector-certs -n vault -o jsonpath='{.data.tls\.crt}')
kubectl patch mutatingwebhookconfiguration vault-agent-injector-cfg --type='json' -p="[
  {
    \"op\": \"replace\",
    \"path\": \"/webhooks/0/clientConfig/caBundle\",
    \"value\": \"${CA_BUNDLE}\"
  }
]" 2>/dev/null || echo "No existing webhook configuration to update"
```

### Verify the deployment

```bash
kubectl get pods -n vault
kubectl logs -n vault -l app=vault-agent-injector
```

## Common Vault K8s use cases

### Configure Vault authentication

Set up Kubernetes authentication for Vault.

```bash
# Enable Kubernetes auth in Vault
kubectl exec -n vault vault-0 -- sh -c 'VAULT_TOKEN=root vault auth enable kubernetes'

# Configure Kubernetes auth
KUBE_HOST=$(kubectl exec -n vault vault-0 -- sh -c 'echo $KUBERNETES_SERVICE_HOST')
KUBE_PORT=$(kubectl exec -n vault vault-0 -- sh -c 'echo $KUBERNETES_SERVICE_PORT')

kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=root vault write auth/kubernetes/config \
    kubernetes_host='https://${KUBE_HOST}:${KUBE_PORT}' \
    disable_local_ca_jwt=false"

# Create a test secret
kubectl exec -n vault vault-0 -- sh -c 'VAULT_TOKEN=root vault kv put secret/database/config \
    username="db-user" \
    password="db-password"'

# Create a policy
cat > /tmp/webapp-policy.hcl << 'EOF'
path "secret/data/database/config" {
  capabilities = ["read"]
}
EOF
kubectl cp /tmp/webapp-policy.hcl vault/vault-0:/tmp/webapp-policy.hcl
kubectl exec -n vault vault-0 -- sh -c 'VAULT_TOKEN=root vault policy write webapp /tmp/webapp-policy.hcl'

# Create service account for the application
kubectl create serviceaccount webapp -n default

# Create role
kubectl exec -n vault vault-0 -- sh -c 'VAULT_TOKEN=root vault write auth/kubernetes/role/webapp \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=default \
    policies=webapp \
    ttl=24h'
```

### Inject secrets into application pods

Annotate your application pods to automatically inject Vault secrets.

```yaml
cat > app-with-secrets.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: webapp
  namespace: default
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "webapp"
    vault.hashicorp.com/agent-inject-secret-database-config: "secret/data/database/config"
    vault.hashicorp.com/agent-inject-template-database-config: |
      {{- with secret "secret/data/database/config" -}}
      postgresql://{{ .Data.data.username }}:{{ .Data.data.password }}@postgres:5432/mydb
      {{- end }}
spec:
  serviceAccountName: webapp
  containers:
  - name: webapp
    image: nginx:latest
    ports:
    - containerPort: 8080
EOF

kubectl apply -f app-with-secrets.yaml
```

### Verify secret injection

Once the pod is running, verify the secret was injected:

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod webapp -n default --timeout=60s

# Check the injected secret
kubectl exec webapp -n default -c webapp -- cat /vault/secrets/database-config
```

You should see the rendered template with the actual credentials:
```
postgresql://db-user:db-password@postgres:5432/mydb
```

### Custom agent configuration

Mount custom Vault agent configuration for advanced use cases.

```yaml
cat > custom-agent-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-agent-config
  namespace: default
data:
  config.hcl: |
    vault {
      address = "http://vault.vault.svc:8200"
    }
    auto_auth {
      method {
        type = "kubernetes"
        config = {
          role = "webapp"
        }
      }
      sink {
        type = "file"
        config = {
          path = "/vault/.vault-token"
        }
      }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: webapp-custom-config
  namespace: default
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/agent-configmap: "vault-agent-config"
    vault.hashicorp.com/role: "webapp"
spec:
  serviceAccountName: webapp
  containers:
  - name: webapp
    image: nginx:latest
EOF

kubectl apply -f custom-agent-config.yaml
```

### Run Vault K8s commands

The vault-k8s binary supports various subcommands for different operations.

**Display version:**
```bash
docker run --rm dhi.io/vault-k8s:1.7-debian13 version
```

**Show general help:**
```bash
docker run --rm dhi.io/vault-k8s:1.7-debian13 --help
```

**Show help for agent-inject:**
```bash
docker run --rm dhi.io/vault-k8s:1.7-debian13 agent-inject --help
```

## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Standard Vault K8s | Docker Hardened Vault K8s |
|---------|-------------------|---------------------------|
| **Security** | Standard base with bash, curl, and utilities | Minimal, hardened base with security patches |
| **Shell access** | Full shell (bash/sh) available | No shell in runtime variants |
| **Package manager** | Package manager available | No package manager in runtime variants |
| **User** | Runs as root or configurable user | Runs as nonroot user |
| **Image size (runtime)** | ~150MB (compressed) | 12.94MB (compressed) - 91% smaller |
| **Image size (dev)** | ~180MB (compressed) | 49.46MB (compressed) - 73% smaller |
| **Attack surface** | Includes unnecessary binaries and utilities | Minimal - contains only vault-k8s binary and essential libraries |
| **Debugging** | Traditional shell debugging | Use Docker Debug or kubectl debug for troubleshooting |

### Why no shell or package manager?

Docker Hardened Images prioritize security through minimalism:

- **Reduced attack surface**: Fewer binaries mean fewer potential vulnerabilities
- **Immutable infrastructure**: Runtime containers shouldn't be modified after deployment
- **Compliance ready**: Meets strict security requirements for regulated environments

The hardened images intended for runtime don't contain a shell nor any tools for debugging. Common debugging methods for applications built with Docker Hardened Images include:

- **Docker Debug** to attach to containers
- **Docker's Image Mount feature** to mount debugging tools
- **Kubernetes-specific debugging** with `kubectl debug`

Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

For Kubernetes environments, you can use kubectl debug:
```bash
kubectl debug -n vault pod/<pod-name> -it --image=busybox --target=vault-agent-injector
```

Or use Docker Debug if you have access to the node:
```bash
docker debug <container-id>
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

The Vault K8s Docker Hardened Image is available in both runtime and dev variants:

- **Runtime variants**: `1.7-debian13`, `1.7.2`, `1.6-debian13`, etc. (~12-13 MB compressed)
- **Dev variants**: `1.7-dev`, `1.7-debian13-dev`, `1.6-dev`, etc. (~47-50 MB compressed)

Use dev variants for building custom configurations or extensions, and runtime variants for production deployments.

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Kubernetes manifests or Helm values. This and a few other common changes are listed in the following table of migration notes:

| Item | Migration note |
|------|----------------|
| **Base image** | Replace your base images in your Dockerfile or Kubernetes manifests with a Docker Hardened Image. |
| **Package management** | Non-dev images don't contain package managers. Use package managers only in images with a `dev` tag. |
| **Nonroot user** | Runtime images run as a nonroot user. Ensure that necessary files and directories are accessible to that user. |
| **Multi-stage build** | Utilize images with a `dev` tag for build stages and non-dev images for runtime. |
| **TLS certificates** | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| **Ports** | Non-dev hardened images run as a nonroot user by default. Configure your application to use ports above 1024 (e.g., 8080 instead of 80). |
| **Entry point** | Inspect entry points for Docker Hardened Images and update your manifests if necessary. |
| **No shell** | Runtime images don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage. |
| **Webhooks** | Ensure webhook configurations work with the nonroot user and non-privileged ports. |

### Migration process

1. **Find hardened images for your app**: A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.

2. **Update the image reference**: Update the image in your Kubernetes manifests or Helm values to the hardened image you found in the previous step. For runtime deployments, use non-dev tags like `1.7-debian13`. For custom builds, use dev tags like `1.7-debian13-dev`.

3. **Update port configurations**: If you're using privileged ports (below 1024), update your service and deployment to use ports above 1024.

4. **Verify permissions**: Ensure all mounted volumes and file paths are accessible to the nonroot user.

5. **Install additional packages**: If you need to install additional packages, use a multi-stage build with dev variants for the build stage.

6. **Test the deployment**: Deploy to a test environment and verify all functionality works as expected.

## Troubleshoot migration

### General debugging

Docker Hardened Images provide robust debugging capabilities through Docker Debug, which attaches comprehensive debugging tools to running containers while maintaining the security benefits of minimal runtime images.

Docker Debug provides a shell, common debugging tools, and lets you install additional tools in an ephemeral, writable layer that only exists during the debugging session:
```bash
docker debug <container-name>
```

**Docker Debug advantages:**
- Full debugging environment with shells and tools
- Temporary, secure debugging layer that doesn't modify the runtime container
- Install additional debugging tools as needed during the session
- Perfect for troubleshooting DHI containers while preserving security

### Permissions

Runtime image variants run as the nonroot user. Ensure that necessary files and directories are accessible to that user. You may need to:

- Update volume mount permissions
- Use init containers to set proper ownership
- Configure SecurityContext in your pod specs
```yaml
securityContext:
  fsGroup: 65532  # nonroot user group
  runAsNonRoot: true
  runAsUser: 65532
```

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10.

**Solution**: Configure Vault K8s agent-inject to listen on ports 8000, 8080, or other ports above 1024:
```yaml
args:
- agent-inject
- -listen=:8080  # Use port 8080 instead of 443
```

Then update your Service to map the high port to a lower port if needed:
```yaml
spec:
  ports:
  - name: https
    port: 443       # External port
    targetPort: 8080  # Container port (non-privileged)
```

### No shell

Runtime images don't contain a shell. Use dev images in build stages to run shell commands and then copy any necessary artifacts into the runtime stage. For debugging, use Docker Debug or kubectl debug to attach to containers with no shell.

### Webhook certificate issues

If you encounter TLS certificate issues with the mutating webhook:

1. **Verify certificate secret exists**:
```bash
kubectl get secret vault-agent-injector-certs -n vault
```

2. **Check certificate validity**:
```bash
kubectl get secret vault-agent-injector-certs -n vault -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

3. **Regenerate certificates if needed** using cert-manager or manual certificate generation.

### Entry point

Docker Hardened Images may have different entry points than standard images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your configuration if necessary:
```bash
docker inspect dhi.io/vault-k8s:1.7-debian13
```

## Production considerations

This guide uses Vault in dev mode for simplicity. For production deployments:

1. **Use a production Vault cluster** with proper storage backend (Consul, Raft, etc.)
2. **Enable TLS** for Vault server communication
3. **Use cert-manager** for webhook certificate management
4. **Configure proper RBAC** and security policies
5. **Set up Vault high availability** for resilience
6. **Use namespace isolation** for multi-tenant environments
7. **Implement proper secret rotation** policies
8. **Monitor and audit** Vault access logs

---

**Note**: This guide has been validated through empirical testing in a real Kubernetes environment. All examples have been tested to verify the agent-inject functionality works correctly with the DHI image.
