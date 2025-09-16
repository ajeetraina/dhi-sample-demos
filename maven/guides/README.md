
## Key insight from our testing:

- Every single Maven DHI image tag includes "-dev"
- There are zero runtime variants - no tags without "-dev"

- Maven DHI images are exclusively build-time tools.
- Unlike Node.js DHI images that have both dev and runtime variants, Maven only needs dev variants because:
- Maven builds applications, it doesn't run them
- After Maven creates JARs/WARs, you run those with JRE/JDK images
- There's no use case for a "runtime Maven container"
- The Docker image already has mvn as its ENTRYPOINT, so we're accidentally running mvn mvn clean compile.


```
docker run --rm dockerdevrel/dhi-maven:3.9-jdk21-alpine3.22-dev --version

Apache Maven 3.9.11 (3e54c93a704957b63ee3494413a2b544fd3d825b)
Maven home: /opt/java/apache-maven-3.9.11
Java version: 21.0.8, vendor: Eclipse Adoptium, runtime: /opt/java/openjdk/21
Default locale: en_US, platform encoding: UTF-8
OS name: "linux", version: "6.10.14-linuxkit", arch: "aarch64", family: "unix"
ajeetsraina  maven-test  ♥ 21:24 
```


```
docker run --rm dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev mvn --version
Unable to find image 'dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev' locally
3.9-jdk21-debian13-dev: Pulling from dockerdevrel/dhi-maven
8a3a567b114b: Pull complete
98a19d752655: Pull complete
1f1f552d657d: Pull complete
94394d448f8c: Pull complete
f7416c6f8c92: Pull complete
fd18d252b4cc: Pull complete
be7e09c40798: Pull complete
43bfbe40f409: Pull complete
fb5dff75ec85: Pull complete
Digest: sha256:ae74a3320c0495c00e14ac718fce4ff03aa8908d86612fe26762959ddf1519ab
Status: Downloaded newer image for dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev
Apache Maven 3.9.11 (3e54c93a704957b63ee3494413a2b544fd3d825b)
Maven home: /opt/java/apache-maven-3.9.11
Java version: 21.0.8, vendor: Eclipse Adoptium, runtime: /opt/java/openjdk/21
Default locale: en_US, platform encoding: UTF-8
OS name: "linux", version: "6.10.14-linuxkit", arch: "aarch64", family: "unix"
```

```
# Let's check the actual ENTRYPOINT/CMD
docker inspect dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev | grep -A5 -B5 "EntryPoint\|Cmd"
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "digest": "sha256:ae74a3320c0495c00e14ac718fce4ff03aa8908d86612fe26762959ddf1519ab",
            "size": 1536
        },
        "Config": {
            "Cmd": [
                ""
            ],
            "Entrypoint": [
                "mvn"
            ],
```

## Simple Compile Command 

Let's test the simpler compile command first. But you'll need a basic Maven project structure for it to work.

## Quick setup:

```
mkdir maven-test && cd maven-test
```

Create minimal pom.xml:

```
cat > pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.example</groupId>
    <artifactId>maven-dhi-test</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    
    <properties>
        <maven.compiler.source>21</maven.compiler.source>
        <maven.compiler.target>21</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
</project>
EOF
```

## Create minimal Java class:

```
mkdir -p src/main/java/com/example
cat > src/main/java/com/example/App.java << 'EOF'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("Hello from Maven DHI!");
    }
}
EOF
```

Now test the compile command:

```
docker run --rm -v "$(pwd)":/app -w /app dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev mvn clean compile
```

This should:

Download dependencies (first time will be slower)
Compile the Java source
Create target/classes/ directory with compiled .class files
Show successful build output


### Actual Result

```
ajeetsraina  maven-test  ♥ 21:17  docker run --rm -v "$(pwd)":/app -w /app dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev mvn clean compile
[INFO] Scanning for projects...
[INFO]
[INFO] ---------------------< com.example:maven-dhi-test >---------------------
[INFO] Building maven-dhi-test 1.0.0
[INFO]   from pom.xml
[INFO] --------------------------------[ jar ]---------------------------------
[INFO] ------------------------------------------------------------------------
[INFO] BUILD FAILURE
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  0.082 s
[INFO] Finished at: 2025-09-16T15:47:11Z
[INFO] ------------------------------------------------------------------------
[ERROR] Unknown lifecycle phase "mvn". You must specify a valid lifecycle phase or a goal in the format <plugin-prefix>:<goal> or <plugin-group-id>:<plugin-artifact-id>[:<plugin-version>]:<goal>. Available lifecycle phases are: pre-clean, clean, post-clean, validate, initialize, generate-sources, process-sources, generate-resources, process-resources, compile, process-classes, generate-test-sources, process-test-sources, generate-test-resources, process-test-resources, test-compile, process-test-classes, test, prepare-package, package, pre-integration-test, integration-test, post-integration-test, verify, install, deploy, pre-site, site, post-site, site-deploy. -> [Help 1]
[ERROR]
[ERROR] To see the full stack trace of the errors, re-run Maven with the -e switch.
[ERROR] Re-run Maven using the -X switch to enable full debug logging.
[ERROR]
[ERROR] For more information about the errors and possible solutions, please read the following articles:
[ERROR] [Help 1] http://cwiki.apache.org/confluence/display/MAVEN/LifecyclePhaseNotFoundException
```

Ah! I see the issue. The guide has an error - the Docker image already has mvn as its ENTRYPOINT, so we're accidentally running mvn mvn clean compile.

```
docker run --rm -v "$(pwd)":/app -w /app dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev clean compile
```

The Docker image already has mvn as the ENTRYPOINT, so all commands in the guide accidentally run mvn mvn ... instead of mvn ....



```
ajeetsraina  maven-test  ♥ 23:09  docker volume create maven-repo
maven-repo
ajeetsraina  maven-test  ♥ 23:10  docker run --rm \
    -v "$(pwd)":/app -w /app \
    -v maven-repo:/root/.m2 \
    dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev \
    clean package
[INFO] Scanning for projects...
[INFO]
[INFO] ---------------------< com.example:maven-dhi-test >---------------------
[INFO] Building maven-dhi-test 1.0.0
[INFO]   from pom.xml
[INFO] --------------------------------[ jar ]---------------------------------
[INFO]
[INFO] --- clean:3.2.0:clean (default-clean) @ maven-dhi-test ---
[INFO] Deleting /app/target
[INFO]
[INFO] --- resources:3.3.1:resources (default-resources) @ maven-dhi-test ---
[INFO] skip non existing resourceDirectory /app/src/main/resources
[INFO]
[INFO] --- compiler:3.13.0:compile (default-compile) @ maven-dhi-test ---
[INFO] Recompiling the module because of changed source code.
[INFO] Compiling 1 source file with javac [debug target 21] to target/classes
[INFO]
[INFO] --- resources:3.3.1:testResources (default-testResources) @ maven-dhi-test ---
[INFO] skip non existing resourceDirectory /app/src/test/resources
[INFO]
[INFO] --- compiler:3.13.0:testCompile (default-testCompile) @ maven-dhi-test ---
[INFO] No sources to compile
[INFO]
[INFO] --- surefire:3.2.5:test (default-test) @ maven-dhi-test ---
[INFO] No tests to run.
[INFO]
[INFO] --- jar:3.3.0:jar (default-jar) @ maven-dhi-test ---
[INFO] Building jar: /app/target/maven-dhi-test-1.0.0.jar
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  0.907 s
[INFO] Finished at: 2025-09-16T17:40:11Z
[INFO] ------------------------------------------------------------------------
ajeetsraina  maven-test  ♥ 23:10  docker run --rm \
    -v "$(pwd)":/app -w /app \
    -v maven-repo:/root/.m2 \
    dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev \
    clean package
[INFO] Scanning for projects...
^C[INFO]
[INFO] ---------------------< com.example:maven-dhi-test >---------------------
[INFO] Building maven-dhi-test 1.0.0
[INFO]   from pom.xml
[INFO] --------------------------------[ jar ]---------------------------------
ajeetsraina  maven-test  ♥ 23:11  docker build -t my-spring-app .
[+] Building 3.6s (19/19) FINISHED                                            docker:desktop-linux
 => [internal] load build definition from Dockerfile                                          0.0s
 => => transferring dockerfile: 575B                                                          0.0s
 => resolve image config for docker-image://docker.io/docker/dockerfile:1                     2.0s
 => [auth] docker/dockerfile:pull token for registry-1.docker.io                              0.0s
 => CACHED docker-image://docker.io/docker/dockerfile:1@sha256:dabfc0969b935b2080555ace70ee6  0.0s
 => => resolve docker.io/docker/dockerfile:1@sha256:dabfc0969b935b2080555ace70ee69a5261af8a8  0.0s
 => [internal] load metadata for docker.io/dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev      1.3s
 => [internal] load metadata for docker.io/library/eclipse-temurin:21-jre-alpine              1.3s
 => [auth] dockerdevrel/dhi-maven:pull token for registry-1.docker.io                         0.0s
 => [auth] library/eclipse-temurin:pull token for registry-1.docker.io                        0.0s
 => [internal] load .dockerignore                                                             0.0s
 => => transferring context: 2B                                                               0.0s
 => [build 1/5] FROM docker.io/dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev@sha256:ae74a332  0.0s
 => => resolve docker.io/dockerdevrel/dhi-maven:3.9-jdk21-debian13-dev@sha256:ae74a3320c0495  0.0s
 => [runtime 1/3] FROM docker.io/library/eclipse-temurin:21-jre-alpine@sha256:4ca7eff3ab0ef9  0.0s
 => => resolve docker.io/library/eclipse-temurin:21-jre-alpine@sha256:4ca7eff3ab0ef9b41f5fef  0.0s
 => [internal] load build context                                                             0.0s
 => => transferring context: 249B                                                             0.0s
 => CACHED [runtime 2/3] WORKDIR /app                                                         0.0s
 => CACHED [build 2/5] WORKDIR /app                                                           0.0s
 => CACHED [build 3/5] COPY pom.xml .                                                         0.0s
 => CACHED [build 4/5] COPY src ./src                                                         0.0s
 => CACHED [build 5/5] RUN --mount=type=cache,target=/root/.m2     mvn clean package -DskipT  0.0s
 => CACHED [runtime 3/3] COPY --from=build /app/target/*.jar app.jar                          0.0s
 => exporting to image                                                                        0.1s
 => => exporting layers                                                                       0.0s
 => => exporting manifest sha256:4432f9bae3acbfbb9a7a3a079b15c550dcf37282e290e735b190fe42e71  0.0s
 => => exporting config sha256:2d7d60efef03ff72220d0ae38bd81d63420f2c43ba330c15ea01b096e45f5  0.0s
 => => exporting attestation manifest sha256:32aa3575ce8c8a1e6109c25844fda5e0dc1db9cab47f2d9  0.0s
 => => exporting manifest list sha256:d7c2115c3b4bade31f59e932dd8397a549ea86648999a9adbfade8  0.0s
 => => naming to docker.io/library/my-spring-app:latest                                       0.0s
 => => unpacking to docker.io/library/my-spring-app:latest                                    0.0s
ajeetsraina  maven-test  ♥ 23:11  docker run --rm -p 8080:8080 --name my-running-app my-spring-app
Hello from Maven DHI!
ajeetsraina  maven-test  ♥ 23:11 
```
