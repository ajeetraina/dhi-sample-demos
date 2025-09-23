## How to use this image

### Start a Node.js instance

Run the following command to run a Nodejs container. Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```
$ docker run --rm <your-namespace>/dhi-node:<tag> node --version
```

## Quick Start: Hello World Example

Here's a complete, working example that demonstrates how to use Docker Hardened Node.js images with a simple web server.

### Create the application files

**package.json**
```json
{
  "name": "hello-world-app",
  "version": "1.0.0",
  "description": "Simple Node.js hello world server",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js"
  },
  "dependencies": {}
}
```

**src/index.js**
```javascript
const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Hello World from Docker Hardened Node.js!\n');
});

const port = process.env.PORT || 3000;
server.listen(port, '0.0.0.0', () => {
  console.log(`Server running on port ${port}`);
});
```

**Dockerfile**
```dockerfile
# syntax=docker/dockerfile:1
# Use dev variant for building
FROM <your-namespace>/dhi-node:22-dev AS build-stage

ENV NODE_ENV=production
WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install dependencies (though this example has none)
RUN npm ci --omit=dev

# Use runtime variant for final image
FROM <your-namespace>/dhi-node:22 AS runtime-stage

ENV NODE_ENV=production
WORKDIR /usr/src/app

# Copy node_modules from build stage (if any)
COPY --from=build-stage /usr/src/app/node_modules ./node_modules

# Copy application code
COPY src ./src
COPY package*.json ./

# Expose port (use non-privileged port)
EXPOSE 3000

# Start the application
CMD ["node", "src/index.js"]
```

### Build and run the application

```bash
# Build the Docker image
$ docker build -t hello-world-node .

# Run the container
$ docker run --rm -p 3000:3000 --name hello-world-app hello-world-node

# Test the application
$ curl http://localhost:3000
Hello World from Docker Hardened Node.js!
```


## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Docker Official Node.js | Docker Hardened Node.js |
|---------|------------------------|-------------------------|
| **Security** | Standard base with common utilities | Minimal, hardened base with security patches |
| **Shell access** | Full shell (bash/sh) available | No shell in runtime variants |
| **Package manager** | npm/yarn available in all variants | npm/yarn only available in dev variants |
| **User** | Runs as root by default | Runs as nonroot user |
| **Attack surface** | Larger due to additional utilities | Minimal, only essential components |
| **Debugging** | Traditional shell debugging | Use Docker Debug or Image Mount for troubleshooting |


### Why no shell or package manager in runtime variants?

Docker Hardened Images prioritize security through minimalism:

- Reduced attack surface: Fewer binaries mean fewer potential vulnerabilities
- Immutable infrastructure: Runtime containers shouldn't be modified after deployment
- Compliance ready: Meets strict security requirements for regulated environments

The hardened images intended for runtime don't contain a shell nor any tools for debugging. Common debugging methods for applications built with Docker Hardened Images include:

- [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to containers
- Docker's Image Mount feature to mount debugging tools
- Application-level logging and monitoring

Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

- For example, you can use Docker Debug:

```
$ docker debug <container-name>
```

to get a debug shell into any container or image, even if they don't contain a shell.

## Image variants

Docker Hardened Images come in different variants depending on their intended
use. Image variants are identified by their tag.

- Runtime variants are designed to run your application in production. These
  images are intended to be used either directly or as the `FROM` image in the
  final stage of a multi-stage build. These images typically:
    - Run as a nonroot user
    - Do not include a shell or a package manager
    - Contain only the minimal set of libraries needed to run the app

- Build-time variants typically include `dev` in the tag name and are
  intended for use in the first stage of a multi-stage Dockerfile. These images
  typically:
    - Run as the root user
    - Include a shell and package manager
    - Are used to build or compile applications

To view the image variants and get more information about them, select the
**Tags** tab for this repository, and then select a tag.

### FIPS variants

FIPS variants include `fips` in the variant name and tag. They come in both runtime and build-time variants. These variants use cryptographic modules that have been validated under FIPS 140, a U.S. government standard for secure cryptographic operations. 

Docker Hardened Node.js images include FIPS-compliant variants for environments requiring Federal Information Processing Standards compliance.


#### Steps to verify FIPS:

```shell
# Check FIPS status (should return 1 for enabled)
$ docker run --rm <your-namespace>/dhi-node:<version>-fips \
  node -e "console.log('FIPS status:', require('crypto').getFips ? require('crypto').getFips() : 'FIPS method not available')"

# Verify cipher restrictions (FIPS has significantly fewer available)
$ docker run --rm <your-namespace>/dhi-node:<version>-fips \
  node -e "console.log('FIPS ciphers:', require('crypto').getCiphers().length)"

$ docker run --rm <your-namespace>/dhi-node:<version> \
  node -e "console.log('Non-FIPS ciphers:', require('crypto').getCiphers().length)"

# Test disabled cryptographic functions (MD5 disabled in FIPS)
$ docker run --rm <your-namespace>/dhi-node:<version>-fips \
  node -e "
  try {
    require('crypto').createHash('md5').update('test').digest('hex');
    console.log('MD5: Available');
  } catch(e) {
    console.log('MD5: Disabled -', e.message);
  }"
 ```

#### Runtime requirements specific to FIPS:

- FIPS mode enforces stricter cryptographic standards
- Weak cryptographic functions like MD5 are disabled and will fail at runtime
- Applications using restricted algorithms may need modification
- Only FIPS-approved cryptographic algorithms are available (~60% fewer than non-FIPS)


## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your
Dockerfile. At minimum, you must update the base image in your existing
Dockerfile to a Docker Hardened Image. This and a few other common changes are
listed in the following table of migration notes.

| Item               | Migration note                                                                                                                                                                                                                                                                                                               |
|:-------------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Base image         | Replace your base images in your Dockerfile with a Docker Hardened Image.                                                                                                                                                                                                                                                    |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a `dev` tag.                                                                                                                                                                                                  |
| Nonroot user       | By default, non-dev images, intended for runtime, run as a nonroot user. Ensure that necessary files and directories are accessible to that user.                                                                                                                                                                            |
| Multi-stage build  | Utilize images with a `dev` tag for build stages and non-dev images for runtime. For binary executables, use a `static` image for runtime.                                                                                                                                                                                   || No shell           | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage.                                                                                                                                                  |

### Migrate to a Docker Hardened Image

The following steps outline the general migration process.

1. Find hardened images for your app.

   A hardened image may have several variants. Inspect the image tags and find
   the image variant that meets your needs. Node.js images are available in versions 18, 20, 22 and 24

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

LocalStack DHI runtime images contain basic shell access but lack most system utilities for debugging. Common commands like ls, cat, id, ps, find, and rm are removed. The recommended method for debugging applications built with Docker Hardened Images is to use `docker debug` to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Permissions

By default, runtime image variants run as the non-root user. Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so LocalStack running as the nonroot user can access them.

### Privileged ports

LocalStack DHI runs as a nonroot user by default. However, LocalStack is pre-configured to use non-privileged ports (4566, 5678, 4510-4559), so privileged port binding is not a concern for LocalStack deployments.

### System utilities

LocalStack DHI runtime images lack most system utilities that some services need for initialization. Missing utilities include rm, cp, mv (file operations), objcopy (from binutils), tar, gzip (archive utilities), and id, ps, find (system inspection tools). Since LocalStack DHI has no dev variants, use multi-stage builds with standard LocalStack for tasks requiring full system utilities, then copy necessary artifacts to the DHI runtime stage.

### Service dependencies

Some LocalStack services require Java runtime or system utilities not available in the minimized image. Services like DynamoDB and Lambda may fail during initialization with "command not found" errors for utilities like rm or objcopy. Core services like S3, SQS, SNS, STS, and IAM work reliably in the hardened environment.

### Entry point

LocalStack DHI images use localstack-supervisor as the entry point, which may differ from other LocalStack distributions. Use docker inspect to inspect entry points for Docker Hardened Images and update your deployment configuration if necessary.
