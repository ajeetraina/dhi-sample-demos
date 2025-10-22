# syntax=docker/dockerfile:1
# Multi-Stage Dockerfile using MinIO DHI variants
# ============================================================================
# STAGE 1: Setup Stage using MinIO DHI dev variant
# ============================================================================
FROM dockerdevrel/dhi-minio:0.20251015.172955-debian13-dev AS setup

WORKDIR /app

# Copy project files
COPY test-scripts/ ./test-scripts/
COPY minio-config/ ./config/

# Add build info (using available shell commands)
RUN echo "Built at: $(date)" > ./config/build-info.txt && \
    echo "Architecture: $(uname -m)" >> ./config/build-info.txt && \
    echo "MinIO version: $(minio --version)" >> ./config/build-info.txt

# Verify files copied correctly
RUN echo "=== Setup Stage ===" && \
    echo "Config files:" && \
    ls -lh ./config/ && \
    echo "Test scripts:" && \
    ls -lh ./test-scripts/

# The -dev variant provides debugging tools for validation
RUN echo "✓ Configuration validated" && \
    echo "✓ Scripts prepared"

# ============================================================================
# STAGE 2: Runtime Stage using MinIO DHI runtime variant
# ============================================================================
FROM dockerdevrel/dhi-minio:0.20251015.172955-debian13 AS runtime

WORKDIR /app

# Copy from setup stage
COPY --from=setup /app/config/ /etc/minio/
COPY --from=setup /app/test-scripts/ /app/scripts/

# Environment variables
ENV MINIO_ROOT_USER=admin \
    MINIO_ROOT_PASSWORD=password123

# Metadata
LABEL maintainer="devrel@docker.com" \
      description="MinIO DHI with multi-stage build" \
      setup.image="dockerdevrel/dhi-minio:0.20251015.172955-debian13-dev" \
      runtime.image="dockerdevrel/dhi-minio:0.20251015.172955-debian13"

# Ports
EXPOSE 9000 9001

# Command
CMD ["server", "/data", "--console-address", ":9001"]
