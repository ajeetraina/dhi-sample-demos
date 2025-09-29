```
==========================================
DHI Validation Report
==========================================
Image: dockerdevrel/dhi-grist:1.7.3-debian13
Container: 754
Date: Mon Sep 29 15:13:14 IST 2025

1. NONROOT USER
-------------------------------------------
   Current UID: 65532
   Current GID: 65532
   Current User: nonroot
[PASS] Running as nonroot user (UID: 65532)

2. SHELL AVAILABILITY
-------------------------------------------
   Found: /bin/sh
   Found: /bin/bash
[FAIL] Shell exists (DHI runtime should not have shell)

3. PACKAGE MANAGERS
-------------------------------------------
[PASS] No package managers found (as expected for DHI runtime)

4. TLS CERTIFICATES
-------------------------------------------
[FAIL] No TLS certificates found

5. PORT CONFIGURATION
-------------------------------------------
[INFO] Could not verify port (netstat may not be available)

6. ENTRY POINT AND CMD
-------------------------------------------
   Entrypoint: [/grist/sandbox/docker_entrypoint.sh]
   Cmd: [node /grist/sandbox/supervisor.mjs]

7. FILE SYSTEM PERMISSIONS
-------------------------------------------
   /persist: Writable by nonroot user: YES
   /grist: Writable by nonroot user: NO
   /tmp: Writable by nonroot user: YES

8. DEVELOPMENT TOOLS CHECK
-------------------------------------------
[PASS] No development tools found (minimal image)

9. IMAGE INFORMATION
-------------------------------------------
   Image size: 1.09GB
PRETTY_NAME="Docker Hardened Images/Debian GNU/Linux 13 (trixie)"

==========================================
VALIDATION SUMMARY
==========================================
Passed:   5
Failed:   2
Warnings: 1

Overall: Image has some deviations from standard DHI runtime pattern
```
