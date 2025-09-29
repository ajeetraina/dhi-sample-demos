## How to use this image


### Run a Grist container

To run a Grist container, run the following command. Replace
`<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```
$ docker run -p 8484:8484 <your-namespace>/dhi-grist:<tag>
```

Then visit http://localhost:8484 in your browser.

### Run with persistent data

```
docker run -d \
  -p 8484:8484 \
  -v grist-data:/persist \
  -e GRIST_DEFAULT_EMAIL=admin@company.com \
  <your-namespace>/dhi-grist:<tag>
```

## Docker Compose example

```
services:
  grist:
    image: <your-namespace>/dhi-grist:<tag>
    ports:
      - "8484:8484"
    volumes:
      - grist-data:/persist
    environment:
      - GRIST_DEFAULT_EMAIL=admin@company.com
      - GRIST_SINGLE_ORG=myorg
    restart: unless-stopped

volumes:
  grist-data:
```

## Image variants

Docker Hardened Images typically come in different variants depending on their intended use. Image variants are identified by their tag.
For dockerdevrel/dhi-grist, only ONE variant is currently available:

- Tag: 1.7.3-debian13 (runtime variant)

Runtime variants are designed to run your application in production. These images are intended to be used directly. Runtime variants typically:

- Run as a nonroot user
- Do not include package managers
- Contain only the minimal set of libraries needed to run the app

Note: No dev variant exists for dhi-grist. Multi-stage builds and package installation are not possible with this image.


To view the image variants and get more information about them, select the
**Tags** tab for this repository, and then select a tag.

## Migrate to a Docker Hardened Image

Important for dockerdevrel/dhi-grist: This is a pre-built, ready-to-run Grist application. Use it directly via docker run rather than as a base image in a Dockerfile. Most migration scenarios below do not apply to this image.


| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
|:-------------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Base image         |  This is a pre-built application - use directly via docker run, not as a base image in Dockerfile.                                                                                                                                                                                                                                                  |
| Package management | No package managers present (no apt, apk, yum). Cannot install additional packages at runtime.                                                                                                                                                                                                  |
| Nonroot user       | Runs as UID 65532 (user: nonroot). Writable directories: /persist and /tmp. Application directory /grist is read-only.                                                                                                                                                                            |
| Multi-stage build  |  Only one variant exists (1.7.3-debian13). No dev or static variants available.                                                                                                                                                                       |
| TLS certificates   | System CA certificates are not present. However, Node.js includes its own certificate bundle, so HTTPS connections work correctly. No action needed for Grist functionality.                                                                                                                                                                                                         |
| Ports              | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can’t bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. |
| Entry point        | Custom entrypoint configured: `/grist/sandbox/docker_entrypoint.sh` with `CMD: node /grist/sandbox/supervisor.mjs`                                                                                                                                |


The following steps outline the general migration process.

1. Find hardened images for your app.

   A hardened image may have several variants. Inspect the image tags and find
   the image variant that meets your needs.

2. Update the base image in your Dockerfile.

   Update the base image in your application's Dockerfile to the hardened image
   you found in the previous step. For framework images, this is typically going
   to be an image tagged as `dev` because it has the tools needed to install
   packages and dependencies.

3. For multi-stage Dockerfiles, update the runtime image in your Dockerfile.

   To ensure that your final image is as minimal as possible, you should use a
   multi-stage build. All stages in your Dockerfile should use a hardened image.
   While intermediary stages will typically use images tagged as `dev`, your
   final runtime stage should use a non-dev image variant.

4. Install additional packages

   Docker Hardened Images contain minimal packages in order to reduce the
   potential attack surface. You may need to install additional packages in your
   Dockerfile. To view if a package manager is available for an image variant,
   select the **Tags** tab for this repository. To view what packages are
   already installed in an image variant, select the **Tags** tab for this
   repository, and then select a tag.

   Only images tagged as `dev` typically have package managers. You should use a
   multi-stage Dockerfile to install the packages. Install the packages in the
   build stage that uses a `dev` image. Then, if needed, copy any necessary
   artifacts to the runtime stage that uses a non-dev image.

   For Alpine-based images, you can use `apk` to install packages. For
   Debian-based images, you can use `apt-get` to install packages.

## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for
debugging. The recommended method for debugging applications built with Docker
Hardened Images is to use [Docker
Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to these
containers. Docker Debug provides a shell, common debugging tools, and lets you
install other tools in an ephemeral, writable layer that only exists during the
debugging session.

### Permissions

By default image variants intended for runtime, run as a nonroot user. Ensure
that necessary files and directories are accessible to that user. You may
need to copy files to different directories or change permissions so your
application running as a nonroot user can access them.

 To view the user for an image variant, select the **Tags** tab for this
 repository.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result,
applications in these images can't bind to privileged ports (below 1024) when
running in Kubernetes or in Docker Engine versions older than 20.10. To avoid
issues, configure your application to listen on port 1025 or higher inside the
container, even if you map it to a lower port on the host. For example, `docker
run -p 80:8080 my-image` will work because the port inside the container is 8080,
and `docker run -p 80:81 my-image` won't work because the port inside the
container is 81.

### No shell

By default, image variants intended for runtime don't contain a shell. Use `dev`
images in build stages to run shell commands and then copy any necessary
artifacts into the runtime stage. In addition, use Docker Debug to debug
containers with no shell.

 To see if a shell is available in an image variant and which one, select the
 **Tags** tab for this repository.

### Entry point

Docker Hardened Images may have different entry points than images such as
Docker Official Images.

To view the Entrypoint or CMD defined for an image variant, select the **Tags**
tab for this repository, select a tag, and then select the **Specifications**
tab.
