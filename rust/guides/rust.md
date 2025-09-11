
# How to use this image


## Start a Rust image

Test the Rust toolchain:

```
$ docker run --rm <your-namespace>/dhi-rust:<tag> rustc --version
```

Or quickly test with a simple Rust program:

```bash
# Create a simple Rust program
echo 'fn main() {
    println!("Hello from DHI Rust!");
}' > hello.rs

# Compile and run with the dev variant (has Rust toolchain)
docker run -v $(pwd):/app -w /app --rm \
  <your-namespace>/dhi-rust:<tag>-dev rustc hello.rs -o hello && ./hello
```

## Common Rust use cases

### Run a Rust application

Compile and run your Rust application by mounting your local project:

```bash
# Create a simple Rust program
echo 'fn main() {
    println!("Hello from DHI Rust!");
}' > main.rs

# Compile and run with dev variant
docker run -v $(pwd):/app -w /app \
  <your-namespace>/dhi-rust:<tag>-dev rustc main.rs -o main && ./main
```

**Note**: This uses volume mounting for development. For production, use the multi-stage build approach shown below.

### Quick development and testing

Create and compile a simple Rust HTTP server:

```bash
# Create a basic Cargo project structure
mkdir -p src
echo '[package]
name = "hello-rust"
version = "0.1.0"
edition = "2021"

[dependencies]' > Cargo.toml

# Create a simple HTTP server
echo 'use std::io::prelude::*;
use std::net::{TcpListener, TcpStream};

fn main() {
    let listener = TcpListener::bind("0.0.0.0:8000").unwrap();
    println!("Server running on port 8000");

    for stream in listener.incoming() {
        let stream = stream.unwrap();
        handle_connection(stream);
    }
}

fn handle_connection(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    stream.read(&mut buffer).unwrap();

    let response = "HTTP/1.1 200 OK\r\n\r\nHello from DHI Rust!";
    stream.write(response.as_bytes()).unwrap();
    stream.flush().unwrap();
}' > src/main.rs

# Build and run with dev variant
docker run -v $(pwd):/app -w /app -p 8000:8000 \
  <your-namespace>/dhi-rust:<tag>-dev sh -c "cargo build --release && ./target/release/hello-rust"
```

You should see "Server running on port 8000" and can test with:
```bash
curl http://localhost:8000
```

### Build with dependencies

For projects with external dependencies, use the dev variant to build:

```bash
# Create Cargo.toml with dependencies
echo '[package]
name = "web-server"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
warp = "0.3"' > Cargo.toml

# Create async web server
echo 'use warp::Filter;

#[tokio::main]
async fn main() {
    let hello = warp::path!("hello" / String)
        .map(|name| format!("Hello, {}!", name));

    warp::serve(hello)
        .run(([0, 0, 0, 0], 3030))
        .await;
}' > src/main.rs

# Build with dev variant
docker run -v $(pwd):/app -w /app -p 3030:3030 \
  <your-namespace>/dhi-rust:<tag>-dev sh -c "cargo build --release && ./target/release/web-server"
```

### Multi-stage build for production

For production deployments, use a multi-stage Dockerfile to create minimal, secure images:

**Create the application files:**

```bash
# Create Cargo.toml
echo '[package]
name = "hello-rust"
version = "0.1.0"
edition = "2021"

[dependencies]' > Cargo.toml

# Create the app
echo 'use std::io::prelude::*;
use std::net::{TcpListener, TcpStream};

fn main() {
    let listener = TcpListener::bind("0.0.0.0:8000").unwrap();
    println!("Server running on port 8000");

    for stream in listener.incoming() {
        let stream = stream.unwrap();
        handle_connection(stream);
    }
}

fn handle_connection(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    stream.read(&mut buffer).unwrap();

    let response = "HTTP/1.1 200 OK\\r\\n\\r\\nHello from Docker Hardened Rust!";
    stream.write(response.as_bytes()).unwrap();
    stream.flush().unwrap();
}' > src/main.rs
```

**Create Dockerfile:**

```bash
echo '# Build stage
FROM <your-namespace>/dhi-rust:<tag>-dev AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
COPY src ./src
RUN cargo build --release

# Runtime stage - using static image for minimal footprint
FROM <your-namespace>/dhi-static:<tag>
WORKDIR /app
COPY --from=builder /app/target/release/hello-rust ./server
USER 1001
EXPOSE 8000
CMD ["./server"]' > Dockerfile
```

**Build and run:**

```bash
docker build -t my-rust-app .
docker run -p 8000:8000 my-rust-app
```

You should see "Server running on port 8000" and can test with:
```bash
curl http://localhost:8000
```

## Non-hardened images vs. Docker Hardened Images

### Key advantages

| Feature | Docker Official Rust | Docker Hardened Rust |
|---------|---------------------|----------------------|
| **Security** | Standard base with common utilities | Advanced security hardening with minimal attack surface |
| **Runtime environment** | Full shell and tools available | Secure, production-optimized runtime with essential components only |
| **Package management** | Cargo available in all variants | Secure development workflow: Cargo in dev variants, minimal runtime variants |
| **User security** | Runs as root by default | Secure non-root execution by default |
| **Attack surface** | Larger due to additional utilities | Minimal, carefully curated components |
| **Debugging** | Traditional shell debugging | Advanced debugging with Docker Debug - comprehensive tools without compromising security |
| **Base OS** | Various Alpine/Debian/Ubuntu versions | Security-hardened Alpine or Debian base |
| **Binary deployment** | Full toolchain in runtime | Optimized for static binary deployment with minimal dependencies |

### Why minimal runtime with comprehensive development tools?

Docker Hardened Images provide the best of both worlds through a thoughtful architecture:

- **Enhanced security**: Minimal runtime images reduce attack surface while maintaining full functionality
- **Optimized for Rust**: Perfect for Rust's compile-to-binary workflow - build with full toolchain, deploy minimal binaries
- **Immutable infrastructure**: Runtime containers are designed for deployment stability
- **Compliance ready**: Meets strict security requirements for regulated environments
- **Efficient development**: Dev variants provide comprehensive Rust toolchain when needed

**Advanced debugging capabilities**: Docker Debug provides comprehensive debugging tools through an ephemeral, secure layer that doesn't compromise the runtime container's security posture.

## Image variants

Docker Hardened Images come in different variants depending on their intended use:

### Runtime variants
Designed to run your application in production. These images are intended to be used either directly or as the FROM image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Do not include a shell or package manager
- Contain only the minimal set of libraries needed to run the app
- **For Rust**: Often use `dhi-static` for compiled binaries with minimal dependencies

### Build-time variants
Typically include `dev` in the variant name and are intended for use in the first stage of a multi-stage Dockerfile. These images typically:

- Run as the root user
- Include a shell and package manager
- Include the complete Rust toolchain (rustc, cargo, etc.)
- Are used to build or compile applications

### FIPS variants

Docker Hardened Rust images include FIPS-compliant variants for environments requiring Federal Information Processing Standards compliance.

**FIPS variant naming:**
- Runtime: `<your-namespace>/dhi-rust:<version>-fips`
- Development: `<your-namespace>/dhi-rust:<version>-fips-dev`

**Steps to verify FIPS:**
```bash
# Check FIPS cryptographic libraries in compiled Rust programs
docker run --rm <your-namespace>/dhi-rust:<version>-fips \
  ldd /usr/local/cargo/bin/cargo | grep -i fips

# Verify OpenSSL FIPS mode if available
docker run --rm <your-namespace>/dhi-rust:<version>-fips \
  openssl version -a | grep -i fips
```

**Runtime requirements specific to FIPS:**
- FIPS mode enforces strict cryptographic standards for enhanced security
- Rust applications using cryptographic crates may need FIPS-compatible alternatives
- Applications benefit from verified, FIPS-approved cryptographic operations only
- Curated cryptographic libraries ensure only secure, validated operations

**What changes in FIPS mode:**
- OpenSSL operates in FIPS-approved mode only
- Certain cryptographic crates may be restricted or require FIPS-compatible versions
- Self-tests are performed on cryptographic modules at startup
- Non-compliant crypto operations will fail with specific error messages

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the following table of migration notes:

| Item | Migration note |
|------|----------------|
| **Base image** | Replace your base images in your Dockerfile with a Docker Hardened Image. |
| **Package management** | Non-dev images, intended for runtime, don't contain package managers. Use Cargo only in images with a dev tag. |
| **Nonroot user** | By default, non-dev images, intended for runtime, run as a nonroot user. Ensure that necessary files and directories are accessible to that user. |
| **Multi-stage build** | Utilize images with a dev tag for build stages and static images for runtime. For Rust binaries, use `dhi-static` for runtime. |
| **TLS certificates** | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| **Ports** | Non-dev hardened images run as a nonroot user by default. Configure your Rust application to use ports above 1024. |
| **Entry point** | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| **No shell** | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage. |

### Migration process

1. **Find hardened images for your app.**
   A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs. Rust images are available in multiple versions.

2. **Update the base image in your Dockerfile.**
   Update the base image in your application's Dockerfile to the hardened image you found in the previous step. For Rust applications, this is typically going to be an image tagged as `dev` because it has the Rust toolchain needed to compile applications.

   Example:
   ```dockerfile
   FROM <your-namespace>/dhi-rust:<version>-dev
   ```

3. **For multi-stage Dockerfiles, update the runtime image in your Dockerfile.**
   To ensure that your final image is as minimal as possible, you should use a multi-stage build. Use dev images for build stages and static images for runtime. For Rust applications, consider using `dhi-static` for the runtime stage since Rust compiles to self-contained binaries.

4. **Install additional packages**
   Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to install additional packages in your Dockerfile.

   Only images tagged as `dev` typically have package managers. You should use a multi-stage Dockerfile to install the packages. Install the packages in the build stage that uses a dev image. Then copy any necessary artifacts to the runtime stage that uses a minimal image.

## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. Docker Hardened Images provide robust debugging capabilities through **Docker Debug**, which attaches comprehensive debugging tools to running containers while maintaining the security benefits of minimal runtime images.

**Docker Debug** provides a shell, common debugging tools, and lets you install additional tools in an ephemeral, writable layer that only exists during the debugging session:

```bash
docker debug <container-name>
```

**Docker Debug advantages:**
- Full debugging environment with shells and tools
- Temporary, secure debugging layer that doesn't modify the runtime container
- Install additional debugging tools as needed during the session
- Perfect for troubleshooting DHI containers while preserving security

### Permissions

By default image variants intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to that user. You may need to copy files to different directories or change permissions so your application running as a nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. Configure your Rust applications to listen on ports 8000, 8080, or other ports above 1024.

### No shell

By default, image variants intended for runtime don't contain a shell. Use dev images in build stages to run shell commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.

