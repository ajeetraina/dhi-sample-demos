## Prerequisite

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/alpine-base:<tag>`
- Mirrored image: `<your-namespace>/dhi-alpine-base:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

### What's included in this Alpine Base image

This Docker Hardened Image includes:

- BusyBox
- Alpine utilities
- Package Manager: apk
- CIS benchmark compliance (runtime), FIPS 140 + STIG + CIS compliance (FIPS variant)

## Start an Alpine Base instance

On startup, the image initializes BusyBox and Alpine utilities.

Run the following command and replace `<tag>` with the image variant you want to run (for example,
`latest`):

```console
$ docker run --rm dhi.io/alpine-base:<tag> sh
```

## Common Alpine Base use cases

### Minimal Container Operations
### Security Testing
### Base for Custom Applications
### Deploy Alpine Base in Kubernetes

- [Link to DHI K8s authentication instructions](https://example.com/k8s/auth)
- Create namespace:

```console
$ kubectl create namespace alpine-base-test
```

- Example Deployment YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alpine-base-deployment
  namespace: alpine-base-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alpine-base
  template:
    metadata:
      labels:
        app: alpine-base
    spec:
      containers:
      - name: alpine-base
        image: dhi.io/alpine-base:<tag>
        imagePullSecrets:
          - name: dhi-registry-secret
        securityContext:
          runAsUser: 0
      nodeSelector:
        kubernetes.io/os: linux
```

- Note: This setup runs as root (`runAsUser: 0`) because it may require shell access for initial scripts.

- Deploy with:

```console
$ kubectl apply -f alpine-base-deployment.yaml
$ kubectl get pods -n alpine-base-test
```

## Official Docker image (DOI) vs Docker Hardened Image (DHI)

| Feature            | DOI (`library/alpine`) | DHI (`dhi.io/alpine-base`)   |
|--------------------|------------------------|-----------------------------|
| User               | root                   | root                         |
| Shell              | /bin/ash               | /bin/ash                     |
| Package manager    | apk                    | apk                          |
| Entrypoint         | /bin/sh                | /bin/sh                      |
| Uncompressed size  | ~5MB                   | ~4MB                         |
| Zero CVE commitment| No                     | Yes                          |
| FIPS variant       | No                     | Yes (FIPS + STIG + CIS)      |
| Base OS            | Alpine                 | Docker Hardened Images (Alpine) |
| Compliance labels  | None                   | CIS (runtime), FIPS+STIG+CIS (fips) |
| ENV: PATH          | /usr/sbin:/sbin:/bin   | ...                          |
| Architectures      | amd64, arm64           | amd64, arm64                 |

## Image variants

Docker Hardened Images come in different variants depending on their intended use. Image variants are identified by
their tag.

- **Runtime variants** - production use, nonroot, minimal base
- **Dev variants** - root user, shell, package manager included

To view the image variants and get more information about them, select the **Tags** tab for this repository, and then
select a tag.

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your
Dockerfile. At minimum, you must update the base image in your existing
Dockerfile to a Docker Hardened Image. This and a few other common changes are
listed in the following table of migration notes:

| Item               | Migration note                                                                                                                                                                     |
| :----------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image         | Replace your base images in your Dockerfile with a Docker Hardened Image.                                                                                                          |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a dev tag.                                                           |
| Non-root user      | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user.                         |
| Multi-stage build  | Utilize images with a dev tag for build stages and non-dev images for runtime. For binary executables, use a static image for runtime.                                             |
| TLS certificates   | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates.                                                                 |
| Ports              | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. |
| Entry point        | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| No shell           | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage.        |

The following steps outline the general migration process.

1. **Find hardened images for your app.**

   A hardened image may have several variants. Inspect the image tags and
   find the image variant that meets your needs.

1. **Update the base image in your Dockerfile.**

   Update the base image in your application's Dockerfile to the hardened
   image you found in the previous step. For framework images, this is
typically going to be an image tagged as dev because it has the tools
   needed to install packages and dependencies.

1. **For multi-stage Dockerfiles, update the runtime image in your Dockerfile.**

   To ensure that your final image is as minimal as possible, you should
   use a multi-stage build. All stages in your Dockerfile should use a
   hardened image. While intermediary stages will typically use images
   tagged as dev, your final runtime stage should use a non-dev image variant.

1. **Install additional packages**

   Docker Hardened Images contain minimal packages in order to reduce the
   potential attack surface. You may need to install additional packages in
your Dockerfile. Inspect the image variants to identify which packages are
   already installed.

   Only images tagged as dev typically have package managers. You should use
a multi-stage Dockerfile to install the packages. Install the packages in
the build stage that uses a dev image. Then, if needed, copy any necessary
   artifacts to the runtime stage that uses a non-dev image.

   For Alpine-based images, you can use apk to install packages. For
   Debian-based images, you can use apt-get to install packages.

## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools
for debugging. The recommended method for debugging applications built with
Docker Hardened Images is to use
[Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to
attach to these containers. Docker Debug provides a shell, common debugging
tools, and lets you install other tools in an ephemeral, writable layer that
only exists during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot user.
Ensure that necessary files and directories are accessible to the nonroot user.
You may need to copy files to different directories or change permissions so
your application running as the nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result,
applications in these images can't bind to privileged ports (below 1024) when
running in Kubernetes or in Docker Engine versions older than 20.10.

### No shell

By default, image variants intended for runtime don't contain a shell. Use
dev images in build stages to run shell commands and then copy any necessary
artifacts into the runtime stage. In addition, use Docker Debug to debug
containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as
Docker Official Images. Use `docker inspect` to inspect entry points for
Docker Hardened Images and update your Dockerfile if necessary.
