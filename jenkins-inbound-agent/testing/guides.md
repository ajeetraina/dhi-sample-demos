
## Prerequisite

All examples in this guide use the public image. If you've mirrored
the repository for your own use (for example, to your Docker Hub
namespace), update your commands to reference the mirrored image
instead of the public one.

For example:

- Public image: `dhi.io/jenkins-inbound-agent:<tag>`
- Mirrored image: `<your-namespace>/dhi-jenkins-inbound-agent:<tag>`

For the examples, you must first use `docker login dhi.io` to
authenticate to the registry to pull the images.

### What's included in this Jenkins Inbound Agent image

This Docker Hardened Image includes:

- Jenkins agent binaries and CLI
- Networking tools (curl, wget)
- CIS benchmark compliance (runtime), FIPS 140 + STIG + CIS
compliance (FIPS variant)



## Start a Jenkins Inbound Agent instance

On startup, the Jenkins Inbound Agent connects to a Jenkins server
to listen for tasks. It requires the Jenkins controller URL and
secret.

Run the following command and replace `<tag>` with the image variant
you want to run (for example, `example-tag`):


$ docker run --rm dhi.io/jenkins-inbound-agent:<tag> <flags> -url
<JENKINS_URL> <SECRET> <AGENT_NAME>



## Common Jenkins Inbound Agent use cases

### Connect Jenkins Inbound Agent to Jenkins controller
### Use Jenkins Inbound Agent with specific labels for tasks
### Scale Jenkins Inbound Agent instances dynamically
### Deploy Jenkins Inbound Agent in Kubernetes

For the Kubernetes deployment of the Jenkins Inbound Agent, follow
these steps:

- Authenticate to DHI in Kubernetes by consulting [DHI Kubernetes
authentication instructions](
https://docs.docker.com/registry/insecure/).
- Create a namespace for the deployment:


$ kubectl create namespace jenkins



- Use the following Deployment YAML. Note the use of
`imagePullSecrets` for DHI authentication.


apiVersion: apps/v1 kind: Deployment metadata: name: jenkins-agent
namespace: jenkins spec: replicas: 3 selector: matchLabels: app:
jenkins-agent template: metadata: labels: app: jenkins-agent spec:
containers:

- name: jenkins-agent

image: dhi.io/jenkins-inbound-agent:<tag> args: ["-url", "<JENKINS_URL>",
"<SECRET>", "<AGENT_NAME>"] imagePullPolicy: Always imagePullSecrets:

- name: <secret name>

securityContext: runAsUser: 65532 restartPolicy: Always



**Note**: The instance runs as a nonroot user for security best
practices. This ensures compliance with the least privilege
principle.

- Deploy with:


$ kubectl apply -f jenkins-agent-deployment.yaml $ kubectl get pods -n
jenkins



## Official Docker image (DOI) vs Docker Hardened Image (DHI)

| Feature            | DOI (`jenkins/jenkins-inbound-agent`) | DHI (
`dhi.io/jenkins-inbound-agent`) |
|--------------------|--------------------------------------|--------
-----------------------------|
| User               | root                                 | 65532
(nonroot)                     |
| Shell              | /bin/bash                            | None
|
| Package manager    | apt-get                              | None
|
| Entrypoint         | java -jar agent.jar                  | Custom
entrypoint                   |
| Uncompressed size  | Varies                               |
Smaller size                        |
| Zero CVE commitment| No                                   | Yes
|
| FIPS variant       | No                                   | Yes
(FIPS + STIG + CIS)             |
| Base OS            | Debian                               | Docker
Hardened Images (Debian 13)  |
| Compliance labels  | None                                 | CIS
(runtime), FIPS+STIG+CIS (fips) |
| ENV: JENKINS_AGENT | Yes                                  | Yes
|
| Architectures      | amd64, arm64                         | amd64,
arm64                        |



## Image variants

Docker Hardened Images come in different variants depending on their
intended use. Image variants are identified by their tag.

- **Runtime variants** - production use, nonroot, no shell/pkg
manager
- **FIPS variants** - FIPS 140 + STIG + CIS compliance

To view the image variants and get more information about them,
select the **Tags** tab for this repository, and then select a tag.



## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must
update your Dockerfile. At minimum, you must update the base image
in your existing Dockerfile to a Docker Hardened Image. This and a
few other common changes are listed in the following table of
migration notes:

| Item               | Migration note

|
| :----------------- |
:--------------------------------------------------------------------
---------------------------------------------------------------------
---------------------------------------- |
| Base image         | Replace your base images in your Dockerfile
with a Docker Hardened Image.
|
| Package management | Non-dev images, intended for runtime, don't
contain package managers. Use package managers only in images with a
dev tag.                                                           |
| Non-root user      | By default, non-dev images, intended for
runtime, run as the nonroot user. Ensure that necessary files and
directories are accessible to the nonroot user.
|
| Multi-stage build  | Utilize images with a dev tag for build
stages and non-dev images for runtime. For binary executables, use a
static image for runtime.
|
| TLS certificates   | Docker Hardened Images contain standard TLS
certificates by default. There is no need to install TLS
certificates.
|
| Ports              | Non-dev hardened images run as a nonroot user
by default. As a result, applications in these images can't bind to
privileged ports (below 1024) when running in Kubernetes or in
Docker Engine versions older than 20.10. To avoid issues, configure
your application to listen on port 1025 or higher inside the
container. |
| Entry point        | Docker Hardened Images may have different
entry points than images such as Docker Official Images. Inspect
entry points for Docker Hardened Images and update your Dockerfile
if necessary. |
| No shell           | By default, non-dev images, intended for
runtime, don't contain a shell. Use dev images in build stages to
run shell commands and then copy artifacts to the runtime stage.
|

The following steps outline the general migration process.

1. **Find hardened images for your app.**

A hardened image may have several variants. Inspect the image
tags and find the image variant that meets your needs.

1. **Update the base image in your Dockerfile.**

Update the base image in your application's Dockerfile to the
hardened image you found in the previous step. For framework images,
this is typically going to be an image tagged as dev because it has
the tools needed to install packages and dependencies.

1. **For multi-stage Dockerfiles, update the runtime image in your
Dockerfile.**

To ensure that your final image is as minimal as possible, you
should use a multi-stage build. All stages in your Dockerfile should
use a hardened image. While intermediary stages will typically use
images tagged as dev, your final runtime stage should use a non-dev
image variant.

1. **Install additional packages**

Docker Hardened Images contain minimal packages in order to
reduce the potential attack surface. You may need to install
additional packages in your Dockerfile. Inspect the image variants
to identify which packages are already installed.

Only images tagged as dev typically have package managers. You
should use a multi-stage Dockerfile to install the packages. Install
the packages in the build stage that uses a dev image. Then, if
needed, copy any necessary artifacts to the runtime stage that uses
a non-dev image.

For Alpine-based images, you can use apk to install packages. For
Debian-based images, you can use apt-get to install packages.



## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor
any tools for debugging. The recommended method for debugging
applications built with Docker Hardened Images is to use [Docker
Debug](https://docs.docker.com/reference/cli/docker/debug/) to
attach to these containers. Docker Debug provides a shell, common
debugging tools, and lets you install other tools in an ephemeral,
writable layer that only exists during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot
user. Ensure that necessary files and directories are accessible to
the nonroot user. You may need to copy files to different
directories or change permissions so your application running as the
nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a
result, applications in these images can't bind to privileged ports
(below 1024) when running in Kubernetes or in Docker Engine versions
older than 20.10.

### No shell

By default, image variants intended for runtime don't contain a
shell. Use dev images in build stages to run shell commands and then
copy any necessary artifacts into the runtime stage. In addition,
use Docker Debug to debug containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images
such as Docker Official Images. Use `docker inspect` to inspect
entry points for Docker Hardened Images and update your Dockerfile
if necessary.
