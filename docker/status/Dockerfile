# Tools for status.sh. /host is a skeleton for the host directories mounted in
# proxy.yml, complete enough to chroot into for apt.
FROM alpine:latest
RUN apk add --no-cache coreutils curl jq openssl
RUN mkdir -p /host/dev /host/etc /host/tmp /host/var/cache/apt \
    && ln -s usr/bin /host/bin \
    && ln -s usr/lib /host/lib \
    && ln -s usr/sbin /host/sbin
