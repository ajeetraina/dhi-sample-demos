# How to use this image

## Starting a DHI MySQL instance

```console
$ docker run --name some-mysql -e MYSQL_ROOT_PASSWORD=my-secret-pw -d <your-namespace>/dhi-mysql:<tag>
```

... where `some-mysql` is the name you want to assign to your container, `my-secret-pw` is the password to be set for the MySQL root user and `<tag>` is the tag specifying the MySQL version you want.


### Connect to MySQL from the MySQL command line client

The following command starts another `mysql` container instance and runs the `mysql` command line client against your original DHI MySQL container, allowing you to execute SQL statements against your database instance:

```console
$ docker run -it --network some-network --rm mysql:<tag> mysql -hsome-mysql -uroot -p
```

... where `some-mysql` is the name of your original DHI MySQL container (connected to the `some-network` Docker network).

This image can also be used as a client for non-Docker or remote instances:

```console
$ docker run -it --rm mysql:<tag> mysql -hsome.mysql.host -usome-mysql-user -p
```

## Alternative connection methods

Since DHI MySQL runtime images don't include a shell, you can also connect directly using the MySQL client inside the container:

```console
$ docker exec -it some-mysql mysql -uroot -p
```

**Note**: Due to a known issue with password initialization (see Troubleshooting section), you may need to connect without a password initially and set it manually.

## ... via `docker compose`

Example `compose.yaml` for DHI MySQL:

```yaml
# Use root/example as user/password credentials
services:
  db:
    image: <your-namespace>/dhi-mysql:<tag>
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: example
    ports:
      - "3306:3306"
```

For FIPS compliance:

```yaml
services:
  db:
    image: <your-namespace>/dhi-mysql:<tag>-fips
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: example
    ports:
      - "3306:3306"
```

Run `docker compose up`, wait for it to initialize completely, and connect using any of the methods above.

# Container shell access and viewing MySQL logs

Since DHI MySQL runtime images don't contain a shell, use Docker Debug for shell access:

```console
$ docker debug some-mysql
```

The log is available through Docker's container log:

```console
$ docker logs some-mysql
```

## Using a custom MySQL configuration file

If `/my/custom/config-file.cnf` is the path and name of your custom configuration file, you can start your DHI MySQL container like this:

```console
$ docker run --name some-mysql -v /my/custom:/etc/mysql/conf.d -e MYSQL_ROOT_PASSWORD=my-secret-pw -d <your-namespace>/dhi-mysql:<tag>
```

This will start a new container `some-mysql` where the MySQL instance uses the combined startup settings from the default configuration file and `/etc/mysql/conf.d/config-file.cnf`, with settings from the latter taking precedence.

## Configuration without a `cnf` file

Many configuration options can be passed as flags to `mysqld`. This will give you the flexibility to customize the container without needing a `cnf` file. For example, if you want to change the default encoding and collation for all tables to use UTF-8 (`utf8mb4`) just run the following:

```console
$ docker run --name some-mysql -e MYSQL_ROOT_PASSWORD=my-secret-pw -d <your-namespace>/dhi-mysql:<tag> --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
```

If you would like to see a complete list of available options, just run:

```console
$ docker run -it --rm <your-namespace>/dhi-mysql:<tag> --verbose --help
```

## Environment Variables

When you start the DHI MySQL image, you can adjust the configuration of the MySQL instance by passing one or more environment variables on the `docker run` command line.

### `MYSQL_ROOT_PASSWORD`

This variable is mandatory and specifies the password that will be set for the MySQL `root` superuser account.

### `MYSQL_DATABASE`

This variable is optional and allows you to specify the name of a database to be created on image startup. If a user/password was supplied (see below) then that user will be granted superuser access (corresponding to `GRANT ALL`) to this database.

### `MYSQL_USER`, `MYSQL_PASSWORD`

These variables are optional, used in conjunction to create a new user and to set that user's password. This user will be granted superuser permissions (see above) for the database specified by the `MYSQL_DATABASE` variable. Both variables are required for a user to be created.

### `MYSQL_ALLOW_EMPTY_PASSWORD`

This is an optional variable. Set to a non-empty value, like `yes`, to allow the container to be started with a blank password for the root user. **NOTE**: Setting this variable to `yes` is not recommended unless you really know what you are doing, since this will leave your MySQL instance completely unprotected, allowing anyone to gain complete superuser access.

### `MYSQL_RANDOM_ROOT_PASSWORD`

This is an optional variable. Set to a non-empty value, like `yes`, to generate a random initial password for the root user (using `pwgen`). The generated root password will be printed to stdout (`GENERATED ROOT PASSWORD: .....`).

## FIPS Compliance

DHI MySQL images include FIPS-validated variants for environments requiring Federal Information Processing Standards compliance.

### Verify FIPS mode

```console
$ docker exec some-mysql-fips mysql -uroot -p -e "SHOW VARIABLES LIKE 'ssl_fips_mode';"
```

Expected output for FIPS-enabled images:
```
Variable_name   Value
ssl_fips_mode   ON
```

### Check available ciphers (FIPS has fewer)

```console
$ docker exec some-mysql-fips mysql -uroot -p -e "SHOW STATUS LIKE 'Ssl_cipher_list';"
```

## Initializing a fresh instance

When a container is started for the first time, a new database with the specified name will be created and initialized with the provided configuration variables. Furthermore, it will execute files with extensions `.sh`, `.sql` and `.sql.gz` that are found in `/docker-entrypoint-initdb.d`. Files will be executed in alphabetical order.

```console
$ docker run --name some-mysql -v /my/own/datadir:/var/lib/mysql -v /my/custom:/docker-entrypoint-initdb.d -e MYSQL_ROOT_PASSWORD=my-secret-pw -d <your-namespace>/dhi-mysql:<tag>
```

## Differences from Docker Official MySQL

| Feature | Docker Official MySQL | DHI MySQL |
|---------|----------------------|-----------|
| **Security** | Standard base | Hardened, minimal base |
| **Shell** | Available | Runtime: No shell, Dev: Available |
| **User** | mysql user | nonroot user |
| **FIPS** | Not available | FIPS variants available |
| **Attack surface** | Standard | Minimized |
| **Password initialization** | Reliable | Known bug requiring manual fix |

## Image variants

Docker Hardened Images come in different variants depending on their intended use.

- Runtime variants are designed to run your application in production. These
  images are intended to be used either directly or as the `FROM` image in the
  final stage of a multi-stage build. These images typically:
   - Run as the nonroot user
   - Do not include a shell or a package manager
   - Contain only the minimal set of libraries needed to run the app

- Build-time variants typically include `dev` in the variant name and are
  intended for use in the first stage of a multi-stage Dockerfile. These images
  typically:
   - Run as the root user
   - Include a shell and package manager
   - Are used to build or compile applications

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your
Dockerfile. At minimum, you must update the base image in your existing
Dockerfile to a Docker Hardened Image. This and a few other common changes are
listed in the following table of migration notes.

| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
|:-------------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Base image         | Replace your base images in your Dockerfile with a Docker Hardened Image.                                                                                                                                                                                                                                                    |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a `dev` tag.                                                                                                                                                                                                  |
| Non-root user      | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user.                                                                                                                                                                   |
| Multi-stage build  | Utilize images with a `dev` tag for build stages and non-dev images for runtime. For binary executables, use a `static` image for runtime.                                                                                                                                                                                   |
| TLS certificates   | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates.                                                                                                                                                                                                           |
| Ports              | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can’t bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container. |
| Entry point        | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.                                                                                                                                  |
| No shell           | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage.                                                                                                                                                  |

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
   Dockerfile. Inspect the image variants to identify which packages are already
   installed.

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

By default image variants intended for runtime, run as the nonroot user. Ensure
that necessary files and directories are accessible to the nonroot user. You may
need to copy files to different directories or change permissions so your
application running as the nonroot user can access them.

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

### Entry point

Docker Hardened Images may have different entry points than images such as
Docker Official Images. Use `docker inspect` to inspect entry points for Docker
Hardened Images and update your Dockerfile if necessary.
