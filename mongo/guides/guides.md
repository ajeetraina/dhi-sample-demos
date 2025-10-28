# MongoDB Docker Hardened Images Guide

## Prerequisites

Before you can use any Docker Hardened Image, you must mirror the image repository from the catalog to your organization. To mirror the repository, select either **Mirror to repository** or **View in repository > Mirror to repository**, and then follow the on-screen instructions.

## Start a MongoDB instance

Run the following command and replace `<your-namespace>` with your organization's namespace and `<tag>` with the image variant you want to run.

### Basic MongoDB instance

```bash
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  dockerdevrel/dhi-mongodb:8.0.15
```

This starts MongoDB without authentication.

Important: Runtime variants (without `-dev` in the tag) do not include shell access. Use `-dev` variants when you need shell access for administrative tasks, or use Docker Debug for troubleshooting running containers.

### MongoDB instance with dev variant (includes shell access)

If you need shell access for administrative tasks, use the dev variant:

```bash
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  dockerdevrel/dhi-mongodb:8.0.15-dev
```


### MongoDB with persistent data

```bash
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  -v mongodb_data:/data/db \
  dockerdevrel/dhi-mongodb:8.0.15
```

## Common MongoDB use cases

### Use case 1: Development Setup

Simple setup for local development:

```bash
# Start MongoDB (no auth for development)
docker run -d \
  --name mongodb-dev \
  -p 27017:27017 \
  dockerdevrel/dhi-mongodb:8.0.15-dev

# Initialize with sample data
docker exec mongodb-dev mongosh --eval "
  db = db.getSiblingDB('devdb');
  db.items.insertMany([
    {name: 'Item 1', value: 100},
    {name: 'Item 2', value: 200}
  ]);
  print('Sample data created');
"
```


### Use case 2: Custom Configuration

Advanced configuration for production:

```bash
# Create config
docker volume create mongodb_config

docker run --rm -v mongodb_config:/config alpine sh -c 'cat > /config/mongod.conf << "EOF"
net:
  bindIp: 0.0.0.0
  port: 27017
storage:
  dbPath: /data/db
  wiredTiger:
    engineConfig:
      cacheSizeGB: 2
    collectionConfig:
      blockCompressor: snappy
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
  logRotate: reopen
operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 100
security:
  authorization: enabled
EOF'

# Use the config
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  -v mongodb_data:/data/db \
  -v mongodb_config:/etc/mongo:ro \
  -v mongodb_logs:/var/log/mongodb \
  dockerdevrel/dhi-mongodb:8.0.15-dev \
  --config /etc/mongo/mongod.conf
```


### Application integration with MongoDB

Build a multi-stage application that uses MongoDB as its database backend.

```dockerfile
# Dockerfile
################################################################################
# Create a stage for building the application
FROM /dhi-node:22-debian13-dev AS build
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

################################################################################
# Create runtime stage
FROM /dhi-node:22-debian13
WORKDIR /app

# Copy dependencies from build stage
COPY --from=build /app/node_modules ./node_modules

# Copy application code
COPY . .

# Expose application port
EXPOSE 3000

# Start the application
CMD ["node", "server.js"]
```

Sample application code:

```javascript
// server.js
const express = require('express');
const { MongoClient } = require('mongodb');

const app = express();
const port = 3000;

const mongoUrl = process.env.MONGO_URL || 'mongodb://admin:secure_password@mongodb:27017';
const client = new MongoClient(mongoUrl);

app.use(express.json());

// Connect to MongoDB
async function connectDB() {
  try {
    await client.connect();
    console.log('Connected to MongoDB');
  } catch (err) {
    console.error('MongoDB connection error:', err);
  }
}

app.get('/users', async (req, res) => {
  try {
    const db = client.db('myapp');
    const users = await db.collection('users').find({}).toArray();
    res.json(users);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/users', async (req, res) => {
  try {
    const db = client.db('myapp');
    const result = await db.collection('users').insertOne({
      ...req.body,
      created: new Date()
    });
    res.json({ id: result.insertedId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(port, async () => {
  await connectDB();
  console.log(`Server running on port ${port}`);
});
```


## Non-hardened images vs Docker Hardened Images

### Key differences

| Feature | Docker Official MongoDB | Docker Hardened MongoDB |
|---------|-------------------------|-------------------------|
| Security | Standard base with common utilities | Minimal, hardened base with security patches |
| Shell access | Full shell (bash/sh) available | No shell in runtime variants |
| Package manager | apt available | No package manager in runtime variants |
| User | Runs as mongodb user (UID 999) | Runs as nonroot user |
| Attack surface | Larger due to additional utilities | Minimal, only essential components |
| Debugging | Traditional shell debugging | Use Docker Debug or Image Mount for troubleshooting |

### Why no shell or package manager?

Docker Hardened Images prioritize security through minimalism:

- Reduced attack surface: Fewer binaries mean fewer potential vulnerabilities
- Immutable infrastructure: Runtime containers shouldn't be modified after deployment
- Compliance ready: Meets strict security requirements for regulated environments

The hardened images intended for runtime don't contain a shell nor any tools for debugging. Common debugging methods for applications built with Docker Hardened Images include:

- [Docker Debug](https://docs.docker.com/reference/cli/docker/debug/) to attach to containers
- Docker's Image Mount feature to mount debugging tools
- Ecosystem-specific debugging approaches

Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

For example, you can use Docker Debug:

```bash
docker debug mongodb
```

or mount debugging tools with the Image Mount feature:

```bash
docker run --rm -it --pid container:mongodb \
  --mount=type=image,source=/dhi-busybox,destination=/dbg,ro \
  /dhi-mongodb: /dbg/bin/sh
```

## Image variants

Docker Hardened Images come in different variants depending on their intended use.

Runtime variants are designed to run your application in production. These images are intended to be used either directly or as the `FROM` image in the final stage of a multi-stage build. These images typically:

- Run as the nonroot user
- Do not include a shell or a package manager
- Contain only the minimal set of libraries needed to run the app

Build-time variants typically include `dev` in the variant name and are intended for use in the first stage of a multi-stage Dockerfile. These images typically:

- Run as the root user
- Include a shell and package manager
- Are used to build or compile applications

## Migrate to a Docker Hardened Image

To migrate your application to a Docker Hardened Image, you must update your Dockerfile. At minimum, you must update the base image in your existing Dockerfile to a Docker Hardened Image. This and a few other common changes are listed in the following table of migration notes:

| Item | Migration note |
|------|----------------|
| Base image | Replace your base images in your Dockerfile with a Docker Hardened Image. |
| Package management | Non-dev images, intended for runtime, don't contain package managers. Use package managers only in images with a dev tag. |
| Non-root user | By default, non-dev images, intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. |
| Multi-stage build | Utilize images with a dev tag for build stages and non-dev images for runtime. For binary executables, use a static image for runtime. |
| TLS certificates | Docker Hardened Images contain standard TLS certificates by default. There is no need to install TLS certificates. |
| Ports | Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10. MongoDB default port 27017 works without issues. |
| Entry point | Docker Hardened Images may have different entry points than images such as Docker Official Images. Inspect entry points for Docker Hardened Images and update your Dockerfile if necessary. |
| No shell | By default, non-dev images, intended for runtime, don't contain a shell. Use dev images in build stages to run shell commands and then copy artifacts to the runtime stage. |

The following steps outline the general migration process.

1. **Find hardened images for your app.**
    
    A hardened image may have several variants. Inspect the image tags and find the image variant that meets your needs.
    
2. **Update the base image in your Dockerfile.**
    
    Update the base image in your application's Dockerfile to the hardened image you found in the previous step. For framework images, this is typically going to be an image tagged as dev because it has the tools needed to install packages and dependencies.
    
3. **For multi-stage Dockerfiles, update the runtime image in your Dockerfile.**
    
    To ensure that your final image is as minimal as possible, you should use a multi-stage build. All stages in your Dockerfile should use a hardened image. While intermediary stages will typically use images tagged as dev, your final runtime stage should use a non-dev image variant.
    
4. **Install additional packages**
    
    Docker Hardened Images contain minimal packages in order to reduce the potential attack surface. You may need to install additional packages in your Dockerfile. Inspect the image variants to identify which packages are already installed.
    
    Only images tagged as dev typically have package managers. You should use a multi-stage Dockerfile to install the packages. Install the packages in the build stage that uses a dev image. Then, if needed, copy any necessary artifacts to the runtime stage that uses a non-dev image.
    
    For Alpine-based images, you can use apk to install packages. For Debian-based images, you can use apt-get to install packages.

## Troubleshoot migration

### General debugging

The hardened images intended for runtime don't contain a shell nor any tools for debugging. The recommended method for debugging applications built with Docker Hardened Images is to use [Docker Debug](https://docs.docker.com/engine/reference/commandline/debug/) to attach to these containers. Docker Debug provides a shell, common debugging tools, and lets you install other tools in an ephemeral, writable layer that only exists during the debugging session.

### Permissions

By default image variants intended for runtime, run as the nonroot user. Ensure that necessary files and directories are accessible to the nonroot user. You may need to copy files to different directories or change permissions so your application running as the nonroot user can access them.

### Privileged ports

Non-dev hardened images run as a nonroot user by default. As a result, applications in these images can't bind to privileged ports (below 1024) when running in Kubernetes or in Docker Engine versions older than 20.10.

### No shell

By default, image variants intended for runtime don't contain a shell. Use dev images in build stages to run shell commands and then copy any necessary artifacts into the runtime stage. In addition, use Docker Debug to debug containers with no shell.

### Entry point

Docker Hardened Images may have different entry points than images such as Docker Official Images. Use `docker inspect` to inspect entry points for Docker Hardened Images and update your Dockerfile if necessary.
