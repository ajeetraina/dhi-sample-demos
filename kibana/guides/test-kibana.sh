 sh test-kibana.sh
-e Docker Hardened Kibana - Hands-On Verification
-e ================================================

Enter your namespace (e.g., dockerdevrel): dockerdevrel
-e
Configuration:
  Elasticsearch Image: dockerdevrel/dhi-elasticsearch:9.2.0
  Kibana Image: dockerdevrel/dhi-kibana:9.2.0
  Network: elastic-network-test

-e
================================================
-e STEP 1: Create Docker Network
-e ================================================

-e ✓ Network 'elastic-network-test' created successfully
-e
================================================
-e STEP 2: Start Elasticsearch DHI
-e ================================================

-e ℹ Pulling Elasticsearch image (if not present)...
9.2.0: Pulling from dockerdevrel/dhi-elasticsearch
Digest: sha256:3118dafc3f21e1facd7807a2458bb587c99eec46bd72d28ed32d9c055c73de3f
Status: Image is up to date for dockerdevrel/dhi-elasticsearch:9.2.0
docker.io/dockerdevrel/dhi-elasticsearch:9.2.0
-e ℹ Starting Elasticsearch container...
5f21799755105ea136cecccbbacb2748bfd0743259b328399d73a984a59ff6e4
-e ✓ Elasticsearch container started
-e ℹ Waiting for Elasticsearch to be ready (this may take 60-90 seconds)...
-e ℹ Monitoring logs for 'Cluster health status changed' message...
-e ✓ Elasticsearch is ready - Cluster health is GREEN
-e
================================================
-e STEP 3: Locate Elasticsearch Tools
-e ================================================

-e ℹ Finding Elasticsearch tools location...
-e ✓ Found Elasticsearch tools at: /usr/share/elasticsearch/bin
-e
================================================
-e STEP 4: Create Kibana Service Account Token
-e ================================================

-e ℹ Creating service account token for Kibana...
-e ✓ Service account token created
-e Token: AAEAAWVsYXN0aWMva2li...
-e
================================================
-e STEP 5: Verify Elasticsearch Connectivity
-e ================================================

-e ℹ Testing Elasticsearch API from host with service token...
-e ✓ Elasticsearch API is accessible with service token
-e
================================================
-e STEP 6: Generate Kibana Enrollment Token (Optional)
-e ================================================

-e ℹ Generating enrollment token...
-e ✓ Enrollment token generated
-e Token (first 50 chars): eyJ2ZXIiOiI4LjE0LjAiLCJhZHIiOlsiMTcyLjIwLjAuMjo5Mj...
-e
================================================
-e STEP 7: Start Kibana DHI
-e ================================================

-e ℹ Pulling Kibana image (if not present)...
9.2.0: Pulling from dockerdevrel/dhi-kibana
Digest: sha256:3f6baa7ce45ab478b417d8e44283e5d3017d9f46ba3231fff122a0e4911340e6
Status: Image is up to date for dockerdevrel/dhi-kibana:9.2.0
docker.io/dockerdevrel/dhi-kibana:9.2.0
-e ℹ Starting Kibana with service account token...
fd1b0269d1fe97220c0836f7ef81f5c3cf00d155a80d4ebffa8be2be76e4a6f8
-e ✓ Kibana container started
-e ℹ Waiting for Kibana to be ready (this may take 60-90 seconds)...
-e ✓ Kibana is ready and available
-e
================================================
-e STEP 8: Verify Kibana API
-e ================================================

-e ℹ Checking Kibana status endpoint...
-e ✓ Kibana API is responding correctly
-e Kibana State:
-e
================================================
-e STEP 9: Test Elasticsearch Cluster Health
-e ================================================

-e ℹ Checking cluster health...
-e ✓ Elasticsearch cluster is accessible
-e Cluster Status: green
-e
================================================
-e STEP 10: Index Sample Data
-e ================================================

-e ℹ Creating sample index and documents...
-e ℹ Document indexing response:
-e ℹ Indexing second document...
-e ✓ Second document indexed
-e
================================================
-e STEP 11: Search Indexed Data
-e ================================================

-e ℹ Searching for indexed documents...
-e ℹ Search completed
-e
================================================
-e VERIFICATION COMPLETE - Access Information
-e ================================================

-e ✓ All setup steps completed successfully!

-e Access URLs:
-e   Kibana: http://localhost:5601
-e   Elasticsearch: https://localhost:9200

-e Authentication:
-e   Service Account Token: AAEAAWVsYXN0aWMva2liYW5hL2tpYm...

-e Important: Kibana 9.2.0 requires service account tokens
-e The 'elastic' superuser is no longer supported for Kibana

-e Test Results:
-e   ✓ Network created
-e   ✓ Elasticsearch started and healthy
-e   ✓ Service account token created
-e   ✓ Kibana started with service token
-e   ✓ API endpoints responding
-e   ✓ Sample data indexed
-e   ✓ Search queries working

-e Next Steps:
  1. Open Kibana at http://localhost:5601
  2. Kibana is already authenticated with Elasticsearch
  3. Go to 'Discover' to see your indexed data

-e Containers are running. Press Enter to stop and cleanup...

-e
================================================
-e VERIFICATION SUMMARY
-e ================================================

\033[0;32m✓ All verification steps completed successfully!\033[0m

Verified Components:
  \033[0;32m✓\033[0m Docker network
  \033[0;32m✓\033[0m Elasticsearch DHI (cluster: green)
  \033[0;32m✓\033[0m Service account token authentication
  \033[0;32m✓\033[0m Kibana DHI
  \033[0;32m✓\033[0m Kibana-Elasticsearch connectivity
  \033[0;32m✓\033[0m Data indexing
  \033[0;32m✓\033[0m Search functionality

Docker Hardened Kibana 9.2.0 setup verified!

-e Configuration saved to: kibana-test-config-20251111-210833.txt

-e
Cleaning up test environment...
kibana
elasticsearch
kibana
elasticsearch
elastic-network-test
-e Cleanup complete
