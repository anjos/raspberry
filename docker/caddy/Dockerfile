# Caddy with the Cloudflare DNS plugin, needed for the DNS-01 challenge.
# diun can't track this local image: update with
# docker compose -f proxy.yml -p proxy build --pull && ./manage.sh up proxy
FROM caddy:builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
