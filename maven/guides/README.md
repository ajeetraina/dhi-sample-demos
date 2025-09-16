
## Key insight from our testing:

- Every single Maven DHI image tag includes "-dev"
- There are zero runtime variants - no tags without "-dev"

- Maven DHI images are exclusively build-time tools.
- Unlike Node.js DHI images that have both dev and runtime variants, Maven only needs dev variants because:
- Maven builds applications, it doesn't run them
- After Maven creates JARs/WARs, you run those with JRE/JDK images
- There's no use case for a "runtime Maven container"


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
