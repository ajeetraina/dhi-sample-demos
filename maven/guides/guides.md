# How to use this image

Refer to the [Apache Maven documentation](https://maven.apache.org/guides/) for configuring Maven for your project's needs.

## Start a Maven build

Run the following command to execute Maven commands using a Docker Hardened Image. Replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

```bash
$ docker run --rm <your-namespace>/dhi-maven:<tag>-dev --version
```

**Important**: Maven DHI images have `mvn` as their ENTRYPOINT. When using `docker run`, omit `mvn` from your commands. In Dockerfiles, use `RUN mvn ...` as normal since RUN commands execute in shell context.

## Common Maven use cases

### Build a Maven project

Build your Maven project by mounting your source code and running Maven commands:

```bash
$ docker run --rm -v "$(pwd)":/app -w /app <your-namespace>/dhi-maven:<tag>-dev clean compile
```

### Build and package application artifacts

Create application artifacts like JAR or WAR files by building your Maven project:

```bash
$ docker run --rm -v "$(pwd)":/app -w /app <your-namespace>/dhi-maven:<tag>-dev clean package
```

### Build and run with multi-stage Dockerfile

**Important**: Maven Docker Hardened Images are build-only tools. They contain no runtime variants because Maven builds applications but doesn't run them. You must use multi-stage Dockerfiles to copy build artifacts to appropriate runtime images.

Here's a complete example for a Spring Boot application:

```dockerfile
# syntax=docker/dockerfile:1
# Build stage - Maven DHI for building
FROM <your-namespace>/dhi-maven:<tag>-dev AS build

WORKDIR /app

# Copy dependency files for better caching
COPY pom.xml .
COPY src ./src

# Build the application
RUN --mount=type=cache,target=/root/.m2 \
    mvn clean package -DskipTests

# Runtime stage - JRE for running the application
FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Build with dependency caching

Use Docker volumes to speed up builds by persisting the Maven local repository across builds:

```bash
# Create a persistent volume for Maven dependencies
$ docker volume create maven-repo

# Use the volume for faster subsequent builds
$ docker run --rm \
    -v "$(pwd)":/app -w /app \
    -v maven-repo:/root/.m2 \
    <your-namespace>/dhi-maven:<tag>-dev \
    clean package
```

**Note**: The first build will download dependencies (~4-5 seconds), while subsequent builds use cached dependencies (~0.7-1 seconds). Cache mounts (`--mount type=cache`) only work in Dockerfiles, not with `docker run` commands.

You can then build and run the Docker image:

```bash
$ docker build -t my-spring-app .
$ docker run --rm -p 8080:8080 --name my-running-app my-spring-app
```

## Non-hardened images vs Docker Hardened Images

| Feature | Docker Official Maven | Docker Hardened Maven |
|---------|----------------------|------------------------|
| Security | Standard base with common utilities | Custom hardened Debian with security patches |
| Shell access | Direct shell access | Full shell access (requires ENTRYPOINT override) |
| Package manager | Full package managers (apt, dpkg) | **No package managers (completely removed)** |
| User | Runs as root by default | Runs as root (build environment) |
| Attack surface | Large (424+ utilities, full Ubuntu/Debian) | **Minimal (129 utilities, 70% fewer than standard)** |
| Runtime variants | Available for some use cases | **Not available - build-only tool** |
| Debugging | Traditional shell debugging | Use Docker Debug or ENTRYPOINT override |
| Utilities | Full development toolchain (curl, wget, git, vim, tar, make) | **Extremely minimal (no curl, wget, git, vim, nano, tar, gzip, unzip, make)** |

### Why such extreme minimization?

Docker Hardened Maven images prioritize security through aggressive minimalism:

- **Complete package manager removal**: No way to install additional software during builds
- **Utility reduction**: 70% fewer binaries than standard images (129 vs 424+)
- **Custom hardened OS**: Purpose-built "Docker Hardened Images (Debian)" not standard distributions
- **Essential-only toolset**: Only Maven, JDK, and core build utilities included

The hardened images focus exclusively on providing a secure, minimal Maven build environment. After Maven compiles and packages your application, you run the resulting artifacts with appropriate runtime environments.

## Image variants

Docker Hardened Maven images are **build-time only**. All variants include `dev` in the tag name and are designed for use in build stages of multi-stage Dockerfiles.

### Available variants

Maven DHI images follow this tag pattern: `<maven-version>-jdk<jdk-version>-<os>-dev`

**Maven versions:**
- `3.9.11` - Specific patch version (recommended for production)
- `3.9` - Latest patch of 3.9 series  
- `3` - Latest minor and patch version

**JDK versions:**
- `jdk17` - Java 17 LTS (mature, stable)
- `jdk21` - Java 21 LTS (recommended for new projects)
- `jdk23` - Java 23 (latest features)

**Operating systems:**
- `debian13` - Debian-based (default, ~647MB uncompressed)
- `alpine3.22` - Alpine-based (~578MB uncompressed, ~69MB smaller)



## Migrate to a Docker Hardened Image

To migrate your Maven builds to Docker Hardened Images, you must update your Dockerfile and build process. Since Maven DHI images are build-only, **you must use multi-stage builds**.

| Item | Migration note |
|------|----------------|
| Base image | Replace Maven base images with Docker Hardened Maven dev images in build stages only |
| Multi-stage required | Maven DHI images are build-only. Use multi-stage builds to copy artifacts to runtime images |
| Package management | Package managers are available in all Maven DHI images (all are dev variants) |
| Build user | Maven DHI images run as root during build (appropriate for build environments) |
| Dependency caching | Use Docker cache mounts for `/root/.m2` to persist Maven local repository |
| Settings files | Copy or mount Maven settings.xml if using custom repositories |
| Runtime image selection | Choose appropriate JRE/JDK runtime images that match your build JDK version |
| Entry point | Runtime images define entry points; Maven DHI build images use `mvn` as ENTRYPOINT |

### Migration process

1. **Identify your build requirements**
   
   Choose the appropriate Maven DHI dev variant based on your needs:
   - JDK version matching your application requirements
   - OS preference (Debian for compatibility, Alpine for size)
   - Maven version pinning strategy

2. **Convert to multi-stage build**
   
   Update your Dockerfile to use Maven DHI dev variant in the build stage:

   ```dockerfile
   # Build stage
   FROM <your-namespace>/dhi-maven:<tag>-dev AS build
   # ... Maven build commands ...
   
   # Runtime stage  
   FROM eclipse-temurin:21-jre-alpine AS runtime
   COPY --from=build /app/target/app.jar .
   # ... runtime configuration ...
   ```

3. **Optimize dependency caching**
   
   Copy `pom.xml` before source code and use cache mounts:

   ```dockerfile
   COPY pom.xml .
   RUN --mount=type=cache,target=/root/.m2 mvn dependency:go-offline
   COPY src ./src
   RUN --mount=type=cache,target=/root/.m2 mvn package
   ```

4. **Select appropriate runtime image**
   
   Choose runtime images that match your build environment:
   - Same JDK major version (21 in build → JRE 21 in runtime)
   - Consider security and size requirements
   - Ensure runtime image supports your application type

## Troubleshooting migration

The following are common issues that you may encounter during migration.

### General debugging

Maven DHI images are build-only tools and contain shell access via ENTRYPOINT override. The recommended method for debugging applications built with Docker Hardened Images is to use Docker Debug to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

## Permisions

Maven DHI images run as the root user during builds (appropriate for build environments). When copying build artifacts to runtime stages, ensure that necessary files and directories have appropriate permissions for the runtime image's user context, as runtime images typically run as nonroot users.

## Privileged Ports

Applications built with Maven DHI will typically run in runtime images that use nonroot users by default. As a result, your applications can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. To avoid issues, configure your application to listen on port 1025 or higher inside the container, even if you map it to a lower port on the host. For example, docker run -p 80:8080 my-app will work because the port inside the container is 8080, and docker run -p 80:81 my-app won't work because the port inside the container is 81.


## No shell

Use dev images in build stages to run shell commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers with no shell.

## Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use docker inspect to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.
