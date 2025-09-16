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
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | Limited shell access in build environments |
| Package manager | Package managers available | Package managers available (build-only images) |
| User | Runs as root by default | Runs as root (build environment) |
| Attack surface | Larger due to additional utilities | Minimal, only essential build components |
| Runtime variants | Available for some use cases | **Not available - build-only tool** |
| Debugging | Traditional shell debugging | Use Docker Debug for troubleshooting |

### Why no runtime variants?

Maven is a build tool, not a runtime. After Maven compiles and packages your application, you run the resulting artifacts (JAR, WAR, etc.) with appropriate runtime environments:

- **Spring Boot applications**: Use JRE images like `eclipse-temurin:21-jre-alpine`
- **Web applications**: Use application server images like Tomcat or Jetty  
- **Microservices**: Use minimal JRE or native runtime images

The hardened Maven images focus exclusively on providing a secure, minimal build environment.

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

**Examples:**
- `dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev` - Recommended for most projects
- `dockerdevrel/dhi-maven:3.9-jdk17-alpine3.22-dev` - Smaller size, Java 17
- `dockerdevrel/dhi-maven:3-jdk21-dev` - Always latest Maven 3.x (debian13 default)

To view available image variants, select the Tags tab for this repository.

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

### Dependency resolution issues

**Problem**: Dependencies fail to download or resolve during build.

**Solutions**:
- Mount custom `settings.xml` with repository configurations
- Use cache mounts to persist the Maven local repository across builds
- Verify network connectivity to Maven repositories

```dockerfile
# Custom settings
COPY settings.xml /root/.m2/settings.xml

# Cache mount for dependencies
RUN --mount=type=cache,target=/root/.m2 mvn clean package
```

### Build performance issues

**Problem**: Builds are slow due to repeated dependency downloads.

**Solutions**:
- Use Docker cache mounts for `/root/.m2` directory
- Separate dependency installation from source compilation
- Consider using Maven daemon for repeated local builds

```dockerfile
# Separate dependency download
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn dependency:go-offline

# Then copy source and build
COPY src ./src  
RUN --mount=type=cache,target=/root/.m2 mvn compile
```

### JDK version mismatches

**Problem**: Build succeeds but runtime fails due to JDK version incompatibility.

**Solutions**:
- Ensure build and runtime JDK versions are compatible
- Use same major version for build and runtime (e.g., JDK 21 → JRE 21)
- Consider using JDK runtime images if JRE is insufficient

```dockerfile
# Build with JDK 21
FROM dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev AS build

# Runtime with JRE 21 (compatible)
FROM eclipse-temurin:21-jre-alpine AS runtime
```

### Multi-module project issues

**Problem**: Multi-module Maven projects fail to build correctly.

**Solutions**:
- Copy the entire project structure including parent POM
- Use proper WORKDIR and copy strategies for module dependencies
- Consider building modules in correct dependency order

```dockerfile
# Copy entire project structure
COPY pom.xml .
COPY module1/pom.xml module1/
COPY module2/pom.xml module2/
RUN --mount=type=cache,target=/root/.m2 mvn dependency:go-offline

# Copy all source files
COPY module1/src module1/src
COPY module2/src module2/src
RUN --mount=type=cache,target=/root/.m2 mvn clean package
```

### General debugging

For debugging build issues in Maven DHI containers, use Docker Debug to attach debugging tools:

```bash
$ docker debug <container-name>
```

This provides access to debugging tools and shell access even in minimal build environments.
