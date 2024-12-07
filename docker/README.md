# Docker compose files for server deployment

This repository contains docker-compose files for re-deploying the various service
stacks at your raspberry home server.

# Management

Start with:

```sh
./manage.sh help
```

## Environment variables

Environment variables are configured at `.envrc`.  Fine-tune for adding or removing
variables.

## Secrets

Secrets can be found on your personal notes.  Just copy and paste the various
secret files directly to the interface.

## Configuration files

If you deploy the docker compose stacks available in this repository, volumes
for each service will be automatically created for each service where
applicable.

To re-configure the various services, in case you need to deploy a fresh copy
somehow, the easiest is to copy existing backup files with something like:

```sh
$ docker run --rm -it -v /backup/daily.0/raspberry/data:/backup/STACK_VOLUME -v STACK_VOLUME:/data busybox /bin/sh
(sh) $ rm -rf /data/*
(sh) $ cp -a /backup/* /data/
(sh) $ cp -a /backup/.[a-zA-Z]* /data/
```
