## Prerequisites

All examples in this guide use the public image. If you've mirrored the repository for your own use (for example, to
your Docker Hub namespace), update your commands to reference the mirrored image instead of the public one.

For example:

- Public image: `dhi.io/<repository>:<tag>`
- Mirrored image: `<your-namespace>/dhi-<repository>:<tag>`

For the examples, you must first use `docker login dhi.io` to authenticate to the registry to pull the images.

### What's included in this ClamAV image

This Docker Hardened Image includes:

- ClamAV daemon (`clamd`) for high-performance scanning
- ClamAV scanner (`clamscan`) for on-demand file scanning
- ClamAV daemon scanner (`clamdscan`) for client connections to `clamd`
- FreshClam (`freshclam`) for automatic virus database updates
- Pre-loaded virus signature databases (regular variant) or no databases (base variant)
- Custom entrypoint script (`/usr/local/bin/docker-entrypoint.sh`) that starts both `freshclam` and `clamd`
- CIS benchmark compliance (runtime), FIPS 140 + STIG + CIS compliance (FIPS variant)

## Start a ClamAV instance

Start ClamAV in daemon mode. The default entrypoint starts both `freshclam` (to update virus databases) and `clamd`
(the scanning daemon):

```console
$ docker run --rm -it dhi.io/clamav:1.4
```

ClamAV takes approximately 10-15 seconds to initialize. The entrypoint script polls for the `clamd` socket and reports
`socket found, clamd started.` when the daemon is ready.

> **Note:** On first startup, `freshclam` checks for virus database updates. If the bundled databases are outdated, it
> downloads patches before `clamd` becomes available. Subsequent startups with a persistent volume are faster since
> databases are already up to date.

Verify the user the container runs as:

```console
$ docker run --rm --entrypoint whoami dhi.io/clamav:1.4
clamav
```

The image runs as the `clamav` user by default, not root.

## Common ClamAV use cases

### Update the virus database

The DHI ClamAV comes with two variants:

- The regular variant contains the virus database at the time of image creation.
- The `-base` variant does not contain the virus database and is significantly smaller.

In order to use the `-base` variant or to have an up-to-date virus database, run `freshclam`:

```console
$ docker run --rm --entrypoint freshclam dhi.io/clamav:1.4
```

By default, the virus database is stored within the running container in `/var/lib/clamav`. Use a volume or a bind
mount to share or persist it across short-lived ClamAV containers.

With a volume, first create the volume and attach the container to it:

```console
$ docker volume create clam_db

$ docker run --rm --entrypoint freshclam \
    --mount source=clam_db,target=/var/lib/clamav \
    dhi.io/clamav:1.4
```

On subsequent runs with the same volume, `freshclam` skips already-downloaded databases:

```console
$ docker run --rm --entrypoint freshclam \
    --mount source=clam_db,target=/var/lib/clamav \
    dhi.io/clamav:1.4
ClamAV update process started at ...
daily.cld database is up-to-date (version: 27916, ...)
main.cvd database is up-to-date (version: 63, ...)
bytecode.cvd database is up-to-date (version: 339, ...)
```

With a bind mount, map a local directory to the database path within the container:

```console
$ docker run --rm --entrypoint freshclam \
    --mount type=bind,source=/path/to/databases,target=/var/lib/clamav \
    dhi.io/clamav:1.4
```

### Scan files with clamscan

To scan files, mount the folder to scan as a bind mount and run `clamscan`. This uses the standalone scanner which
loads the virus database on each invocation:

```console
$ docker run --rm --entrypoint clamscan \
    -v /path/to/scan:/scandir \
    dhi.io/clamav:1.4 /scandir
```

Example scanning a single file:

```console
$ echo "This is a safe test file" > /tmp/testfile.txt

$ docker run --rm --entrypoint clamscan \
    -v /tmp/testfile.txt:/scandir/testfile.txt \
    dhi.io/clamav:1.4 /scandir/testfile.txt
/scandir/testfile.txt: OK
----------- SCAN SUMMARY -----------
Known viruses: 3627519
Engine version: 1.4.3
Infected files: 0
```

To verify detection, test with the EICAR test signature:

```console
$ echo -n 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.txt

$ docker run --rm --entrypoint clamscan \
    -v /tmp/eicar.txt:/scandir/eicar.txt \
    dhi.io/clamav:1.4 /scandir/eicar.txt
/scandir/eicar.txt: Eicar-Test-Signature FOUND
----------- SCAN SUMMARY -----------
Known viruses: 3627519
Engine version: 1.4.3
Infected files: 1
```

### Scan files with clamdscan (daemon mode)

For high-throughput scanning, run ClamAV in daemon mode and use `clamdscan` to submit files. The daemon keeps the virus
database loaded in memory, making scans significantly faster (~0.04s vs ~10s per file):

```console
$ docker run -d --name clamav-daemon \
    --mount source=clam_db,target=/var/lib/clamav \
    dhi.io/clamav:1.4
```

Wait for the daemon to become ready (~15 seconds), then scan:

```console
$ docker exec clamav-daemon clamdscan --version
ClamAV 1.4.3/27916/...

$ docker exec clamav-daemon sh -c "echo 'safe test file' > /tmp/test.txt && clamdscan /tmp/test.txt"
/tmp/test.txt: OK
----------- SCAN SUMMARY -----------
Infected files: 0
Time: 0.041 sec (0 m 0 s)
```

### Expose ClamAV as a network service

ClamDScan can also connect over a TCP port or Unix socket for use by external applications:

```console
$ docker run -d --name clamav-daemon \
    -p 3310:3310 \
    --mount source=clam_db,target=/var/lib/clamav \
    dhi.io/clamav:1.4
```

Or via a Unix socket using a bind mount:

```console
$ docker run -d --name clamav-daemon \
    --mount type=bind,source=/path/to/sockets,target=/tmp \
    --mount source=clam_db,target=/var/lib/clamav \
    dhi.io/clamav:1.4
```

### Deploy ClamAV in Kubernetes

Create the namespace and Deployment:

```console
$ kubectl create namespace scanning
```

```yaml
# clamav-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clamav
  namespace: scanning
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clamav
  template:
    metadata:
      labels:
        app: clamav
    spec:
      containers:
      - name: clamav
        image: dhi.io/clamav:1.4
        ports:
        - containerPort: 3310
          name: clamd
        volumeMounts:
        - name: clam-db
          mountPath: /var/lib/clamav
      volumes:
      - name: clam-db
        emptyDir: {}
```

```console
$ kubectl apply -f clamav-deployment.yaml

$ kubectl get pods -n scanning
```

You can find more documentation about using ClamAV at https://docs.clamav.net/manual/Installing/Docker.html.

## Official Docker image (DOI) vs Docker Hardened Image (DHI)

| Feature | DOI (`clamav/clamav`) | DHI (`dhi.io/clamav`) |
|---------|----------------------|----------------------|
| User | root (unset) | `clamav` |
| Shell | Yes (Alpine `sh`) | Yes (`dash`) |
| Package manager | Yes (`apk`) | No |
| Entrypoint | `/init` | `/usr/local/bin/docker-entrypoint.sh` |
| Uncompressed size | 342 MB | 429 MB (regular) / 203 MB (base) / 504 MB (FIPS) |
| Zero CVE commitment | No | Yes |
| FIPS variant | No | Yes (FIPS + STIG + CIS) |
| Base variant | Yes | Yes (no virus database) |
| Base OS | Alpine Linux 3.23.3 | Docker Hardened Images (Debian 13) |
| Compliance labels | None | CIS (runtime), FIPS+STIG+CIS (fips) |
| ENV: TZ | `Etc/UTC` | `Etc/UTC` |
| Architectures | amd64 only | amd64, arm64 |

## Image variants

Docker Hardened Images come in different variants depending on their intended use. Image variants are identified by
their tag. For ClamAV DHI images, the following variants are available:

**Regular variants** are preloaded with the virus signature databases available at the time of the image build. These
are ready to scan immediately on startup and are the recommended choice for most deployments. Regular variants
typically:

- Run as the `clamav` user
- Include a `dash` shell but no package manager
- Contain the ClamAV binaries, configuration, and pre-loaded virus databases
- Include CIS benchmark compliance (`com.docker.dhi.compliance: cis`)

The following regular tags are available:

| Tag | Description |
| :--- | :--- |
| `1.4`, `1.4-debian13` | Latest ClamAV 1.4.x on Debian 13 |
| `1.4.3`, `1.4.3-debian13` | ClamAV 1.4.3 on Debian 13 |

**Base variants** include `-base` in the tag and do not contain the virus signature databases. These are significantly
smaller (203 MB vs 429 MB) and are intended for environments where you manage your own database updates or share
databases across containers via volumes:

| Tag | Description |
| :--- | :--- |
| `1.4-base`, `1.4-debian13-base` | Latest ClamAV 1.4.x base on Debian 13 |
| `1.4.3-base`, `1.4.3-debian13-base` | ClamAV 1.4.3 base on Debian 13 |

**FIPS variants** include `fips` in the tag. These variants use cryptographic modules that have been validated under
FIPS 140, a U.S. government standard for secure cryptographic operations. FIPS variants also include STIG and CIS
compliance (`com.docker.dhi.compliance: fips,stig,cis`). For example, usage of MD5 fails in FIPS variants. Use FIPS
variants in regulated environments such as FedRAMP, government, and financial services:

| Tag | Description |
| :--- | :--- |
| `1-fips`, `1-debian13-fips` | Latest ClamAV 1.x FIPS on Debian 13 |
| `1.5-fips`, `1.5-debian13-fips` | ClamAV 1.5.x FIPS on Debian 13 |
| `1.5.1-fips`, `1.5.1-debian13-fips` | ClamAV 1.5.1 FIPS on Debian 13 |

**FIPS base variants** include both `-base` and `-fips` in the tag. These combine FIPS compliance with the smaller
base image that does not include virus databases:

| Tag | Description |
| :--- | :--- |
| `1-base-fips`, `1-debian13-base-fips` | Latest ClamAV 1.x FIPS base on Debian 13 |

> **Note:** No `dev` variant exists for ClamAV DHI. For debugging, use
> [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to running containers, or use the
> built-in `dash` shell via `docker exec <container> sh -c "<command>"`.

To view the image variants and get more information about them, select the **Tags** tab for this repository, and then
select a tag.

## Migrate to a Docker Hardened Image

| Item | Migration note |
| :--- | :--- |
| Base image | This is a pre-built application. Use directly via `docker run`, not as a base image in a Dockerfile. |
| Package management | No package managers present (no `apt`, `apk`, `yum`). Cannot install additional packages at runtime. |
| Nonroot user | Runs as user `clamav`. Writable directories: `/var/lib/clamav`, `/tmp`. |
| Entrypoint | Custom entrypoint: `/usr/local/bin/docker-entrypoint.sh`. DOI uses `/init`. |
| Shell | `dash` shell is available (unlike many other DHI images). |
| Architectures | DHI supports both amd64 and arm64. DOI supports amd64 only. |

The following steps outline the general migration process.

1. **Find hardened images for your app.**

   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.
   Choose between regular (with virus databases) and base (without databases) variants.

1. **Replace the image reference.**

   Update your `docker run` commands, Compose files, or Kubernetes manifests to reference the DHI image:

   ```console
   $ # Before (DOI)
   $ docker run -d clamav/clamav:1.4

   $ # After (DHI)
   $ docker run -d dhi.io/clamav:1.4
   ```

1. **Update entrypoint overrides if needed.**

   The DHI entrypoint is `/usr/local/bin/docker-entrypoint.sh` (DOI uses `/init`). If you override the entrypoint in
   your configuration, update the path accordingly.

1. **Adjust user and permission settings.**

   DHI runs as the `clamav` user. DOI runs as root by default. If your setup depends on root access, update file
   permissions or volume ownership to be accessible by the `clamav` user.

1. **Verify virus database persistence.**

   Use a named volume or bind mount for `/var/lib/clamav` to persist virus databases across container restarts:

   ```console
   $ docker volume create clam_db
   $ docker run -d --mount source=clam_db,target=/var/lib/clamav dhi.io/clamav:1.4
   ```

## Troubleshoot migration

### General debugging

Docker Hardened Images provide robust debugging capabilities through **Docker Debug**, which attaches comprehensive
debugging tools to running containers while maintaining the security benefits of minimal runtime images.

**Docker Debug** provides a shell, common debugging tools, and lets you install additional tools in an ephemeral,
writable layer that only exists during the debugging session:

```console
$ docker debug <container-name>
```

**Docker Debug advantages:**

- Full debugging environment with shells and tools
- Temporary, secure debugging layer that doesn't modify the runtime container
- Install additional debugging tools as needed during the session
- Perfect for troubleshooting DHI containers while preserving security

> **Note:** Unlike many DHI images, the ClamAV DHI does include a `dash` shell. You can use
> `docker exec <container> sh -c "<command>"` for basic troubleshooting without Docker Debug.

### Permissions

The ClamAV DHI runs as the `clamav` user. Ensure that virus database directories and scan target directories are
accessible to this user. When using bind mounts, verify the host directory permissions allow the `clamav` user (or its
UID) to read and write as needed.

### Slow startup

ClamAV takes approximately 10-15 seconds to start as it loads virus databases into memory. On first startup with the
base variant, `freshclam` must download the full database set (~200 MB), which may take longer depending on network
speed. Use a persistent volume to avoid re-downloading databases on each container restart.

### Entry point

The DHI entrypoint (`/usr/local/bin/docker-entrypoint.sh`) differs from the DOI entrypoint (`/init`). Use
`docker inspect` to verify:

```console
$ docker inspect --format '{{json .Config.Entrypoint}}' dhi.io/clamav:1.4
["/usr/local/bin/docker-entrypoint.sh"]
```

If you need to run ClamAV commands directly (such as `clamscan` or `freshclam`), override the entrypoint:

```console
$ docker run --rm --entrypoint clamscan dhi.io/clamav:1.4 --version
```
