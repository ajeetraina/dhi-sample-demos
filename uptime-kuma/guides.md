## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/<repository>:<tag>`
- Mirrored image: `<your-namespace>/dhi-<repository>:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

### What's included in this Uptime Kuma Hardened image

Uptime Kuma is a self-hosted monitoring tool for websites, services, and infrastructure. It periodically probes endpoints over HTTP(S), TCP, ICMP (ping), DNS, and other protocols, records uptime and latency history, and sends notifications when checks fail. It exposes a web dashboard and a status-page system for sharing service health.

This Docker Hardened Uptime Kuma image includes:

- `node` (the Node.js 24 runtime at `/usr/local/bin/node`)
- The Uptime Kuma application at `/app` (server, built frontend assets, database migrations, and bundled production `node_modules`)

The image declares port `3001/tcp` for the web dashboard and API. The default CMD is `node /app/server/server.js`, so the image runs directly without a wrapper script or entrypoint.

For the following examples, replace `<tag>` with the image variant you want to run. To confirm the correct namespace and repository name of the mirrored repository, select **View in repository**.

### Start an Uptime Kuma instance

To run an Uptime Kuma container:

```bash
$ docker run -d --name uptime-kuma \
    -p 3001:3001 \
    dhi.io/uptime-kuma:<tag>
```

After a few seconds, open `http://localhost:3001/` in a browser. On first boot, Uptime Kuma redirects to `/setup-database`, where you choose a database backend (SQLite, MariaDB, etc.) and create your admin account. Subsequent visits go straight to the dashboard.

To verify the server is responding from the command line:

```bash
$ curl -I http://localhost:3001/
HTTP/1.1 302 Found
Location: /setup-database
```

### Common Uptime Kuma use cases

#### Persist data across container restarts

Uptime Kuma stores its database, uploaded files, screenshots, and TLS certificates in `/app/data`. To preserve them across container restarts and image upgrades, mount a named volume or host directory at that path:

```bash
$ docker run -d --name uptime-kuma \
    -p 3001:3001 \
    -v uptime-kuma-data:/app/data \
    dhi.io/uptime-kuma:<tag>
```

The container runs as UID 1000 (the `node` user). When you use named Docker volumes, ownership is set correctly automatically. When you use a bind mount to a host directory, ensure the host path is writable by UID 1000 (or world-writable for testing).

#### Run with Docker Compose

```yaml
services:
  uptime-kuma:
    image: dhi.io/uptime-kuma:<tag>
    container_name: uptime-kuma
    ports:
      - "3001:3001"
    volumes:
      - uptime-kuma-data:/app/data
    restart: unless-stopped

volumes:
  uptime-kuma-data:
```

Start with `docker compose up -d`. The named volume `uptime-kuma-data` is created automatically and persists across `docker compose down` (use `docker compose down -v` if you want to remove it).

#### Deploy on Kubernetes

For Kubernetes, Uptime Kuma is typically a single-replica `Deployment` backed by a `PersistentVolumeClaim` and fronted by a `Service`. The `Recreate` strategy is recommended because Uptime Kuma writes to a single SQLite file by default; rolling deployments with two replicas writing to the same PVC can corrupt the database.

The `imagePullSecrets` field references a pull secret you must create first for `dhi.io` — see [DHI authentication in Kubernetes](https://docs.docker.com/dhi/how-to/k8s/).

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: uptime-kuma-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: uptime-kuma
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: uptime-kuma
  template:
    metadata:
      labels:
        app: uptime-kuma
    spec:
      imagePullSecrets:
        - name: helm-pull-secret
      containers:
        - name: uptime-kuma
          image: dhi.io/uptime-kuma:<tag>
          ports:
            - name: http
              containerPort: 3001
          volumeMounts:
            - name: data
              mountPath: /app/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: uptime-kuma-data
---
apiVersion: v1
kind: Service
metadata:
  name: uptime-kuma
spec:
  selector:
    app: uptime-kuma
  ports:
    - port: 3001
      targetPort: 3001
```

To verify the deployment:

```bash
$ kubectl port-forward svc/uptime-kuma 3001:3001
$ curl -I http://localhost:3001/
HTTP/1.1 302 Found
Location: /setup-database
```

#### Monitoring HTTP(S) using a browser engine

Uptime Kuma's beta support for monitoring HTTP(S) endpoints using a real browser engine relies on Chromium, which is not packaged in this image by default. The hardened image excludes Chromium to reduce its size and attack surface.

If you require browser-engine monitors, you have two options:

- Build a custom image `FROM dhi.io/uptime-kuma:<tag>-dev` and install Chromium during a multi-stage build. The runtime stage is then reduced from this dev variant.
- Use image customizations through your Docker Hardened Images subscription to add Chromium to a private variant of the image.

All other monitor types (HTTP(S) without browser engine, TCP port, ping, DNS, Docker container, push, gRPC, and so on) work as expected with the default image.

### Non-hardened images vs Docker Hardened Images

#### Key differences

| Feature         | Docker Official Uptime Kuma             | Docker Hardened Uptime Kuma                         |
| --------------- | --------------------------------------- | --------------------------------------------------- |
| Security        | Standard Debian base                    | Minimal, hardened Debian 13 base                    |
| Shell access    | Full shell available                    | No shell                                            |
| Package manager | `apt`, `apt-get`, `dpkg`, `npm` present | No package manager (including no `npm`)             |
| User            | Runs as root (`USER` unset)             | Runs as the `node` user (UID 1000)                  |
| Chromium        | Bundled for browser-engine monitors     | Not bundled                                         |
| Image size      | ~2.5 GB                                 | ~507 MB                                             |
| Attack surface  | Larger due to apt toolchain and Chromium | Reduced — no shell, no package manager, no browser |
| Debugging       | Traditional shell debugging             | Use Docker Debug or Image Mount for troubleshooting |
| Compliance      | None                                    | CIS                                                 |
| Attestations    | None                                    | SBOM, provenance, VEX metadata                      |

These are not generic claims — they reflect direct inspection of the upstream `louislam/uptime-kuma:2` image and `dhi.io/uptime-kuma:<tag>`. The DHI variant runs as a nonroot user, ships without any package manager, excludes Chromium, and is approximately 80% smaller.

### Why no shell?

Uptime Kuma is a Node.js application with no runtime dependency on shell scripts, so the runtime image ships without `bash`, `/bin/sh`, or any other shell. The image also excludes `npm` and `yarn` — the application's `node_modules` is pre-installed at build time, and the running container never needs a package manager.

For debugging, use [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/), which provides an ephemeral shell session:

```bash
$ docker debug uptime-kuma
```

For operational visibility without a shell, the Uptime Kuma dashboard itself, the container's stdout logs, and `docker inspect` already report most of what you need.

### Image variants

Docker Hardened Images come in different variants depending on their intended use.

Runtime variants are designed to run your application in production. These images are intended to be used either directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

- Run as the `node` user (UID 1000)
- Do not include a shell or a package manager
- Contain only the Node.js runtime, the Uptime Kuma application, and the minimal set of libraries needed to run it

Build-time variants include `dev` in the variant name and are intended for use in the first stage of a multi-stage Dockerfile. These images typically:

- Run as the root user
- Include a shell (`bash`) and a system package manager (`apt`)
- Are used to build or compile applications, or to install additional system tooling (such as Chromium) alongside Uptime Kuma

The Uptime Kuma image is published in the following variants:

| Variant          | Tag pattern                                  | User                | Compliance | Availability |
| ---------------- | -------------------------------------------- | ------------------- | ---------- | ------------ |
| Runtime          | `<major>`, `<major>-debian13`                | `node` (UID 1000)   | CIS        | Public       |
| Build-time (dev) | `<major>-dev`, `<major>-debian13-dev`        | root                | CIS        | Public       |

To view all published tags and get more information about each variant, select the **Tags** tab for this repository.

### Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile or runtime configuration. At minimum, you must update the base image to a Docker Hardened Image. This and a few other common changes are listed in the following table of migration notes.

| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
| :----------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image         | Replace your base image with `dhi.io/uptime-kuma:<tag>`.                                                                                                                                                                                                                                                                     |
| Package management | The runtime image doesn't contain a package manager (no `apt`, `apt-get`, `dpkg`, or `npm`). To install additional system tooling such as Chromium, build your own image `FROM dhi.io/uptime-kuma:<tag>-dev` and use `apt-get` in a build stage.                                                                              |
| Non-root user      | The image runs as the `node` user (UID 1000), not the typical DHI UID 65532. Ensure any mounted data directory at `/app/data` is writable by UID 1000. With named Docker volumes this works automatically.                                                                                                                    |
| TLS certificates   | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates for monitoring HTTPS endpoints.                                                                                                                                                                             |
| Ports              | The image declares port 3001. The default is above 1024 and unaffected by the privileged-port restriction for nonroot containers.                                                                                                                                                                                              |
| Entry point        | The image has no ENTRYPOINT; the default CMD is `node /app/server/server.js`. To pass additional Node.js flags or environment variables, set them via `-e` or `--env` flags on the docker run command.                                                                                                                         |
| Browser monitors   | Chromium is not bundled. If you rely on browser-engine HTTP(S) monitors, see [Monitoring HTTP(S) using a browser engine](#monitoring-https-using-a-browser-engine) above.                                                                                                                                                       |
| Image pull secret  | For Kubernetes deployments, create a pull secret for `dhi.io` and reference it in `imagePullSecrets`.                                                                                                                                                                                                                          |

### Troubleshoot migration

The following are common issues that you may encounter during migration.

#### General debugging

The hardened runtime image doesn't contain a shell or any tools for debugging. The recommended method is [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/):

```bash
$ docker debug uptime-kuma
```

For most operational issues, the container's stdout logs are the primary source of information. Uptime Kuma logs every server-side event with a timestamp and a category label (`[SERVER]`, `[SETUP-DATABASE]`, `[MONITOR]`, and so on). View them with:

```bash
$ docker logs uptime-kuma
```

If the server seems stuck on the setup wizard, check that you've completed the database setup at `/setup-database` in your browser — the server will print `Waiting for user action...` until the wizard is completed.

#### Permissions

The image runs as UID 1000 (`node`). Volumes mounted at `/app/data` must be writable by this UID. When using named Docker volumes, ownership is set automatically. When using bind mounts to a host directory:

```bash
$ sudo chown -R 1000:1000 /path/to/host/data
```

#### Privileged ports

The image runs as nonroot, so Uptime Kuma cannot bind to ports below 1024. The default port 3001 is unaffected. If you set `PORT` to a value below 1024, the server will fail to start.

#### Entry point

The image has no ENTRYPOINT; the default CMD is `["node", "/app/server/server.js"]`. To override flags or run a one-off command, supply a complete CMD. For example, to print the Node.js version:

```bash
$ docker run --rm --entrypoint node dhi.io/uptime-kuma:<tag> --version
```

Use `docker inspect` to view the entrypoint and default CMD for a specific tag.
