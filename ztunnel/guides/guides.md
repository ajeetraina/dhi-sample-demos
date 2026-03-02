## How to use this image

All examples in this guide use the public image. If you’ve mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/<repository>:<tag>`
- Mirrored image: `<your-namespace>/dhi-<repository>:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

## Start a ztunnel instance

Before using the image, follow the Istio instructions to
[install the control plane](https://istio.io/latest/docs/ambient/install/helm/).

First follow the
[authentication instructions for DHI in Kubernetes](https://docs.docker.com/dhi/how-to/k8s/#authentication).

Install Ztunnel using the official Helm chart and replace the image using the following command. Replace `<secret name>`
with your Kubernetes image pull secret.

```bash
helm install ztunnel istio/ztunnel -n istio-system --wait \
    --set "imagePullSecrets[0].name=<secret name>" \
    --set image=dhi.io/ztunnel
```

## Common ztunnel use cases

- Istio ambient mesh L4 proxy for service-to-service communication
- Zero-trust networking with mutual TLS authentication
- FIPS-compliant service mesh deployments

## Docker Official Images vs. Docker Hardened Images

This DHI includes security hardening, SBOM generation, and CVE patching not present in upstream Istio images.

## Image variants

### FIPS variants

FIPS variants include `-fips` in the tag name (e.g., `1.27.3-fips`).

**Using FIPS variants:**

```bash
helm install ztunnel istio/ztunnel -n istio-system --wait \
    --set "imagePullSecrets[0].name=<secret name>" \
    --set image=dhi.io/ztunnel
```

**Steps to verify FIPS:**

Verify FIPS mode is active by checking the environment variable:

```bash
kubectl exec -n istio-system <ztunnel-pod> -- env | grep OPENSSL_FIPS
```

Expected output: `OPENSSL_FIPS=1`

**Runtime requirements specific to FIPS:**

- OpenSSL FIPS module
  ([Certificate #4282](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4282))
- FIPS configuration is automatically applied at runtime

**What changes in FIPS mode:**

- Compiled with `--no-default-features --features tls-openssl` instead of default Rustls
- All TLS operations use OpenSSL FIPS module
- Only FIPS-approved cryptographic algorithms are available

**Platform Support:**

- `linux/amd64` (x86_64)
- `linux/arm64` (aarch64)

## Migrate to a Docker Hardened Image

Replace the `image` value in your Helm installation with the DHI ztunnel image reference.

## Troubleshoot migration

No known migration issues.
