# ClickHouse Metrics Exporter DHI - Template-Based Validation Checklist

## 🎯 Validation Priority (Template-Aligned)

### Phase 1: Basic Functionality (CRITICAL - 10 minutes)

#### Test 1: Basic Run Command
```bash
docker run --name my-clickhouse-exporter -d \
  -p 9116:9116 \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6

# Verify it's running
docker ps | grep my-clickhouse-exporter

# Check logs
docker logs my-clickhouse-exporter

# Test metrics endpoint
curl http://localhost:9116/metrics

# Cleanup
docker rm -f my-clickhouse-exporter
```

**Expected**: Container starts, metrics endpoint responds
**Status**: [ ] PASS [ ] FAIL
**Notes**: 

---

#### Test 2: Image Inspection
```bash
# Check user
docker inspect dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6 \
  --format='User: {{.Config.User}}'

# Check entrypoint
docker inspect dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6 \
  --format='Entrypoint: {{.Config.Entrypoint}} | Cmd: {{.Config.Cmd}}'

# Check exposed ports
docker inspect dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6 \
  --format='Ports: {{.Config.ExposedPorts}}'
```

**Expected**: Nonroot user, port 9116 exposed
**Status**: [ ] PASS [ ] FAIL
**Actual User**: _________________
**Actual Port**: _________________

---

#### Test 3: No Shell Verification
```bash
docker run --rm dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6 \
  /bin/sh -c "echo test" 2>&1
```

**Expected**: Error - no shell available
**Status**: [ ] PASS (no shell) [ ] FAIL (shell exists)
**Notes**: 

---

### Phase 2: Use Cases from Guide (CRITICAL - 20 minutes)

#### Use Case 1: Run with Docker Network
```bash
# Create network
docker network create clickhouse-net

# Run ClickHouse server
docker run -d \
  --name clickhouse-server \
  --network clickhouse-net \
  --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  dockerdevrel/dhi-clickhouse-server:25

# Wait for startup
sleep 15

# Run metrics exporter
docker run -d \
  --name clickhouse-exporter \
  --network clickhouse-net \
  -p 9116:9116 \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6

# Wait and check
sleep 5
docker logs clickhouse-exporter

# Test metrics
curl -s http://localhost:9116/metrics | head -n 20

# Cleanup
docker rm -f clickhouse-server clickhouse-exporter
docker network rm clickhouse-net
```

**Status**: [ ] PASS [ ] FAIL
**Metrics collected?**: [ ] Yes [ ] No
**Notes**: 

---

#### Use Case 2: Persistent Configuration
```bash
cat > scrape-config.yml << EOF
metrics:
  - query: "SELECT version() as version"
    name: clickhouse_version_info
    help: "ClickHouse version information"
    labels:
      - version
  - query: "SELECT count() FROM system.tables"
    name: clickhouse_tables_total
    help: "Total number of tables"
EOF

docker run -d \
  --name clickhouse-exporter \
  -p 9116:9116 \
  -v $(pwd)/scrape-config.yml:/config/scrape-config.yml:ro \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CONFIG_FILE=/config/scrape-config.yml \
  dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6

docker logs clickhouse-exporter
docker rm -f clickhouse-exporter
rm scrape-config.yml
```

**Status**: [ ] PASS [ ] FAIL [ ] Config not supported
**Notes**: 

---

#### Use Case 3: Authentication
```bash
docker run -d \
  --name clickhouse-exporter \
  -p 9116:9116 \
  -e CLICKHOUSE_URL=http://clickhouse-server:8123/ \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=mysecretpassword \
  -e EXPORTER_USER=prometheus \
  -e EXPORTER_PASSWORD=exporter_secret \
  dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6

sleep 3
curl -u prometheus:exporter_secret http://localhost:9116/metrics
curl http://localhost:9116/metrics  # Should fail without auth

docker rm -f clickhouse-exporter
```

**Status**: [ ] PASS [ ] FAIL [ ] Auth not supported
**Notes**: 

---

### Phase 3: Troubleshooting Section Validation (10 minutes)

#### Docker Debug
```bash
docker run -d --name test-exporter -p 9116:9116 \
  dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6

docker debug test-exporter

docker rm -f test-exporter
```

**Status**: [ ] Works [ ] Doesn't work [ ] Docker Debug not available
**Notes**: 

---

#### Connection Issues (from Troubleshooting section)
```bash
# Test with invalid ClickHouse URL
docker run -d --name test-exporter \
  -e CLICKHOUSE_URL=http://nonexistent:8123/ \
  dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6

sleep 5
docker logs test-exporter  # Should show connection error

# Check if container stays running
docker ps | grep test-exporter

docker rm -f test-exporter
```

**Container stays running?**: [ ] Yes [ ] No
**Error messages helpful?**: [ ] Yes [ ] No
**Notes**: 

---

### Phase 4: Migration Table Verification (5 minutes)

#### Ports (from migration table)
**Claim**: "The default exporter port 9116 works without issues"
**Status**: [ ] VERIFIED [ ] INCORRECT
**Actual port**: _________________

#### Non-root user
**Claim**: "Images run as the nonroot user"
**Status**: [ ] VERIFIED [ ] INCORRECT
**Actual user/UID**: _________________

#### Configuration approach
**Claim**: "Configuration via environment variables is the recommended approach"
**Status**: [ ] VERIFIED [ ] NEEDS CLARIFICATION
**Notes**: 

---

## 📊 Template Compliance Check

### Required Sections Present
- [ ] Prerequisites
- [ ] Start a ClickHouse Metrics Exporter instance
- [ ] Common use cases (at least 3)
- [ ] Non-hardened images vs Docker Hardened Images
- [ ] Image variants
- [ ] Migrate to a Docker Hardened Image
- [ ] Troubleshoot migration

### Pre-written Sections (Must Not Change)
- [ ] Prerequisites text matches template
- [ ] "Why no shell or package manager?" matches template
- [ ] Image variants explanation matches template
- [ ] Migration table structure matches template
- [ ] Troubleshooting sections match template

### Image-Specific Content Added
- [ ] Basic run command tested
- [ ] Use cases are image-specific and tested
- [ ] Key differences table has image-specific entries
- [ ] Migration notes include image-specific items
- [ ] Connection issues troubleshooting added

---

## 🚨 Critical Claims to Validate

### From "Start a ClickHouse Metrics Exporter instance"
1. **Port 9116**: [ ] VERIFIED [ ] INCORRECT
2. **Environment variables work**: [ ] VERIFIED [ ] PARTIAL [ ] INCORRECT
   - CLICKHOUSE_URL: [ ] Works
   - CLICKHOUSE_USER: [ ] Works
   - CLICKHOUSE_PASSWORD: [ ] Works

### From Use Cases
1. **Docker network integration works**: [ ] VERIFIED [ ] INCORRECT
2. **Config file mounting works**: [ ] VERIFIED [ ] NOT SUPPORTED [ ] INCORRECT
3. **Authentication works**: [ ] VERIFIED [ ] NOT SUPPORTED [ ] INCORRECT

### From Non-hardened comparison
1. **No shell in runtime**: [ ] VERIFIED [ ] INCORRECT
2. **No package manager**: [ ] VERIFIED [ ] INCORRECT
3. **Runs as nonroot**: [ ] VERIFIED [ ] INCORRECT

---

## 📝 Required Updates Based on Testing

### Section: Start instance
- [ ] No updates needed
- [ ] Updates needed: _________________

### Section: Use Case 1 (Docker network)
- [ ] No updates needed
- [ ] Updates needed: _________________

### Section: Use Case 2 (Config file)
- [ ] No updates needed
- [ ] Updates needed: _________________
- [ ] Remove section (not supported): [ ]

### Section: Use Case 3 (Authentication)
- [ ] No updates needed
- [ ] Updates needed: _________________
- [ ] Remove section (not supported): [ ]

### Section: Migration table
- [ ] No updates needed
- [ ] Port number needs update: _________________
- [ ] Other updates: _________________

### Section: Troubleshooting
- [ ] No updates needed
- [ ] Add issues found during testing: _________________

---

## ✅ Final Approval Checklist

- [ ] All commands tested and work exactly as documented
- [ ] All use cases tested successfully
- [ ] No untested claims remain in the guide
- [ ] Image-specific content is accurate
- [ ] Pre-written template sections unchanged
- [ ] Template structure followed exactly
- [ ] Guide follows DHI documentation standards
- [ ] Ready for publication

---

## 📋 Quick Validation Script

```bash
#!/bin/bash
# Quick validation of template-based guide

echo "=== Phase 1: Basic Functionality ==="
docker run -d --name test -p 9116:9116 dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6
sleep 3
curl -s http://localhost:9116/metrics | head -n 5
docker rm -f test

echo -e "\n=== Phase 2: Docker Network Use Case ==="
docker network create test-net
docker run -d --name ch-server --network test-net --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_PASSWORD=secret dockerdevrel/dhi-clickhouse-server:25
sleep 15
docker run -d --name ch-exp --network test-net -p 9116:9116 \
  -e CLICKHOUSE_URL=http://ch-server:8123/ \
  -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=secret \
  dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6
sleep 5
curl -s http://localhost:9116/metrics | grep clickhouse | head -n 5
docker rm -f ch-server ch-exp
docker network rm test-net

echo -e "\n=== Phase 3: Image Inspection ==="
docker inspect dockerdevrel/dhi-clickhouse-metrics-exporter:0.25.6 \
  --format='User: {{.Config.User}} | Port: {{.Config.ExposedPorts}}'

echo -e "\n=== Validation Complete ==="
```

**Save as**: `quick-template-validation.sh`
**Run with**: `chmod +x quick-template-validation.sh && ./quick-template-validation.sh`
