## How to use this image

Before you can use any Docker Hardened Image, you must mirror the image repository from the catalog to your organization. To mirror the repository, select either **Mirror to repository** or **View in repository** > **Mirror to repository**, and then follow the on-screen instructions.

### Run a Grist container

To run a Grist container, run the following command. Replace
`<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```
$ docker run -p 8484:8484 <your-namespace>/dhi-grist:<tag>
```

Then visit `http://localhost:8484` in your browser.

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

Docker Hardened Images typically come in different variants depending on their intended use. Image variants are identified by their tag. For Grist DHI images, only ONE variant is currently available:

- Tag: `1.7.3-debian13` (runtime variant)

Runtime variants are designed to run your application in production. These images are intended to be used directly. Runtime variants typically:

- Run as a nonroot user
- Do not include package managers
- Contain only the minimal set of libraries needed to run the app

Note: No `dev` variant exists for `dhi-grist`.


To view the image variants and get more information about them, select the
**Tags** tab for this repository, and then select a tag.

## Migrate to a Docker Hardened Image

Important Note: This is a pre-built, ready-to-run Grist application. Use it directly via docker run rather than as a base image in a Dockerfile. Most migration scenarios below do not apply to this image.


| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
|:-------------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Base image         | This is a pre-built application - use directly via docker run, not as a base image in Dockerfile.                                                                                                                                                                                                                                                  |
| Package management | No package managers present (no apt, apk, yum). Cannot install additional packages at runtime.                                                                                                                                                                                                  |
| Nonroot user       | Runs as UID 65532 (user: nonroot). Writable directories: /persist and /tmp. Application directory /grist is read-only.                                                                                                                                                                            |
| Multi-stage build  | Only one variant exists (1.7.3-debian13). No dev or static variants available.                                                                                                                                                                       |
| TLS certificates   | Node.js includes its own certificate bundle, so HTTPS connections work correctly. No action needed for Grist functionality.                                                                                                                                                                                                         |
| Ports              | Pre-configured to listen on port 8484 (non-privileged). Compatible with nonroot user. No configuration needed. |
| Entry point        | Custom entrypoint configured: `/grist/sandbox/docker_entrypoint.sh` with `CMD: node /grist/sandbox/supervisor.mjs`                                                                                                                                |


## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

For Grist DHI image, shell access is available. Use standard `docker exec` commands:

```
docker exec -it <container-id> /bin/bash
# or
docker exec -it <container-id> sh
```

Alternatively, you can use [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) which provides additional debugging tools in an ephemeral layer. Docker Debug is the recommended method for debugging these containers, as it provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Permissions

Image runs as a nonroot user (UID 65532). Ensure that necessary files and directories are accessible to that user.
For dhi-grist:

- /persist directory is writable (use for data persistence)
- /tmp directory is writable
- /grist directory is read-only

If mounting host directories, ensure they have appropriate permissions:

```
# Create directory with proper permissions
mkdir -p grist-data
chmod 755 grist-data

# Run with volume mount
docker run -p 8484:8484 -v ./grist-data:/persist <your-namespace>/dhi-grist:<tag>
```

To view the user for an image variant, select the Tags tab for this repository.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10.

For `dhi-grist` no action is required. Grist is pre-configured to listen on port 8484 (non-privileged).
For all other applications, you need to configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on the host. For example:

- `docker run -p 80:8080 my-image` ✅ works (internal port is 8080)
- `docker run -p 80:81 my-image` ❌ fails (internal port 81 is still privileged on older Docker versions)

### Shell availability

Check image specifications to determine if a shell is available.

- For dhi-grist: Shell is available (/bin/sh and /bin/bash). Standard docker exec commands work for debugging and running scripts.
- For other DHI images: Some DHI runtime images may not include a shell. For those images, use `docker debug` to access debugging tools.


### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images.
For dhi-grist:

- Entrypoint: `/grist/sandbox/docker_entrypoint.sh`
- CMD: `node /grist/sandbox/supervisor.mjs`
