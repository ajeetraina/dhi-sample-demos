

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



