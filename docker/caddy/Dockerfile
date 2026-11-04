# Caddy with the Cloudflare DNS plugin, needed for the DNS-01 challenge. diun
# can't track this local image: ./manage.sh update rebuilds it.
FROM caddy:builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
# Build record for the status page
RUN mkdir /build && printf '{"built":"%s","version":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$(caddy version | cut -d' ' -f1)" > /build/build.json
