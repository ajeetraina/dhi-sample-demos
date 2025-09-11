

## Building the Nodejs DHI Image

```
docker build -t my-dhi-node-app .
```

```
docker run -p 3000:3000 my-dhi-node-app
```




## Using docker debug

Find out the container name by running the following command:

```
docker ps
CONTAINER ID   IMAGE             COMMAND               CREATED         STATUS         PORTS                                         NAMES
30cc67cf1f90   my-dhi-node-app   "node src/index.js"   6 minutes ago   Up 6 minutes   0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp   objective_bouman
```

Using docker debug:


```
docker debug objective_bouman
Pulling image, this might take a moment...
0.0.42: Pulling from docker/desktop-docker-debug-service
6344f3b9a26c: Pull complete
Digest: sha256:67a2a5ac1d73b71dce4f467e963ad723a230fb1a46a9493ccb4eeed1c866e532
Status: Downloaded newer image for hubproxy.docker.internal:5555/docker/desktop-docker-debug-service:0.0.42
         ▄
     ▄ ▄ ▄  ▀▄▀
   ▄ ▄ ▄ ▄ ▄▇▀  █▀▄ █▀█ █▀▀ █▄▀ █▀▀ █▀█
  ▀████████▀    █▄▀ █▄█ █▄▄ █ █ ██▄ █▀▄
   ▀█████▀                        DEBUG

Builtin commands:
- install [tool1] [tool2] ...    Add Nix packages from: https://search.nixos.org/packages
- uninstall [tool1] [tool2] ...  Uninstall NixOS package(s).
- entrypoint                     Print/lint/run the entrypoint.
- builtins                       Show builtin commands.

Checks:
✓ distro:            Docker Hardened Images/Debian GNU/Linux 13 (trixie)
✓ entrypoint linter: no errors (run 'entrypoint' for details)

This is an attach shell, i.e.:
- Any changes to the container filesystem are visible to the container directly.
- The /nix directory is invisible to the actual container.
                                                                                                         Version: 0.0.42
root@30cc67cf1f90 /usr/src/app [objective_bouman]
docker >
```

This entrypoint command output validates that our DHI container is properly configured:

## Key validations:

- CMD properly set: ['node', 'src/index.js'] in exec form (best practice)
- ENTRYPOINT empty: [] (using CMD only, which is fine)
- Working directory: /usr/src/app as expected
- All lint checks passed: Node binary found, proper form usage


```
> entrypoint
Understand how ENTRYPOINT/CMD work and if they are set correctly.
From CMD in Dockerfile:
 ['node', 'src/index.js']

From ENTRYPOINT in Dockerfile:
 []

The container has been started with following command:

node src/index.js

path: node
args: src/index.js
cwd: /usr/src/app
PATH: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

Lint results:
 PASS: 'node' found
 PASS: no mixing of shell and exec form
 PASS: no double use of shell form

Docs:
- https://docs.docker.com/engine/reference/builder/#cmd
- https://docs.docker.com/engine/reference/builder/#entrypoint
- https://docs.docker.com/engine/reference/builder/#understand-how-cmd-and-entrypoint-interact
root@30cc67cf1f90 /usr/src/app [objective_bouman]
docker >
```

## The Htop Tool

```
> htop
```


<img width="956" height="604" alt="image" src="https://github.com/user-attachments/assets/fbbbd43e-2ce0-48b2-a347-714bdf131add" />


## FIPS Testing

### Test 1. "FIPS mode enforces stricter cryptographic standards"

```
# FIPS variant (restricted)
docker run --rm dockerdevrel/dhi-node:24.8-fips \
  node -e "console.log('FIPS ciphers:', require('crypto').getCiphers().length)"

# Non-FIPS variant (unrestricted) 
docker run --rm dockerdevrel/dhi-node:24-debian13 \
  node -e "console.log('Non-FIPS ciphers:', require('crypto').getCiphers().length)"
```

Result

```
FIPS ciphers: 50
Non-FIPS ciphers: 130
```

This validates the ~60% reduction in available cryptographic algorithms under FIPS mode.

### Test 2: Test MD5 availability (often disabled in FIPS):

```
# FIPS variant - MD5 test
docker run --rm dockerdevrel/dhi-node:24.8-fips \
  node -e "
  try {
    require('crypto').createHash('md5').update('test').digest('hex');
    console.log('MD5: Available');
  } catch(e) {
    console.log('MD5: Disabled -', e.message);
  }"

# Non-FIPS comparison
docker run --rm dockerdevrel/dhi-node:24-debian13 \
  node -e "
  try {
    require('crypto').createHash('md5').update('test').digest('hex');
    console.log('MD5: Available');
  } catch(e) {
    console.log('MD5: Disabled -', e.message);
  }"
```

Result:

```
MD5: Disabled - error:0308010C:digital envelope routines::unsupported
MD5: Available
```
This proves that "Some non-FIPS cryptographic functions may be disabled or fail at runtime" is accurate - MD5 is blocked in FIPS mode as expected since it's considered cryptographically weak.

### Test 3. RC4 cipher availability

Let's check RC4 in FIPS vs non-FIPS

This should show RC4 is also disabled in FIPS mode since it's another weak cipher.

```
docker run --rm dockerdevrel/dhi-node:24.8-fips \
  node -e "console.log('FIPS - RC4 available:', require('crypto').getCiphers().includes('rc4'))"

docker run --rm dockerdevrel/dhi-node:24-debian13 \
  node -e "console.log('Non-FIPS - RC4 available:', require('crypto').getCiphers().includes('rc4'))"
```

RC4 is disabled in both FIPS and non-FIPS variants, which means RC4 removal is not FIPS-specific but rather a general Node.js security decision (RC4 is considered obsolete and insecure).
Summary of our verified FIPS claims:

✅ Verified:

Cipher count reduced: 130 → 50 ciphers in FIPS mode
MD5 hash disabled in FIPS: "digital envelope routines::unsupported"
MD5 hash available in non-FIPS

❌ Not FIPS-specific:

RC4 disabled in both variants (general security, not FIPS restriction)

### Test the performance difference between FIPS and non-FIPS variants

```
# FIPS performance test
docker run --rm dockerdevrel/dhi-node:24.8-fips \
  node -e "
  const start = Date.now();
  for(let i = 0; i < 10000; i++) {
    require('crypto').createHash('sha256').update('test' + i).digest();
  }
  console.log('FIPS time:', Date.now() - start, 'ms');"

# Non-FIPS performance test
docker run --rm dockerdevrel/dhi-node:24-debian13 \
  node -e "
  const start = Date.now();
  for(let i = 0; i < 10000; i++) {
    require('crypto').createHash('sha256').update('test' + i).digest();
  }
  console.log('Non-FIPS time:', Date.now() - start, 'ms');"
```

This will help us verify whether "Performance may be slightly reduced due to FIPS validation overhead" is measurable in practice.
The test performs 10,000 SHA-256 hash operations and measures the time difference between FIPS and non-FIPS modes. SHA-256 is a FIPS-approved algorithm that should work in both variants, so any timing difference would be due to FIPS validation overhead rather than algorithm availability.



Result:

FIPS: 41ms (faster)
Non-FIPS: 56ms (slower)

Interesting! The results contradict our assumption about FIPS performance overhead:.
The FIPS variant actually performed ~27% better than the non-FIPS variant. This challenges our claim that "Performance may be slightly reduced due to FIPS validation overhead."




