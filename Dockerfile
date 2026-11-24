FROM wordpress:cli-2.12.0-php8.6@sha256:8a5eb918e3c5db3ad25ec2aea80fd4701903755a719311343ba27a81e5578a0e AS wp_cli

FROM golang:1.27.4-trixie@sha256:c393c00864b56f4404b3fe4d029e47742fbb53ee11506521d2f3377009ad7a3a AS gosu
RUN CGO_ENABLED=0 GOTOOLCHAIN=local GOBIN=/out go install -trimpath github.com/tianon/gosu@29b939aa5bd4dc588af765b8248f6e39150d2565

FROM mariadb:13.0.2@sha256:54f493ea0d60b621a5bff84e5b20100f8b86b6efa6b79158e04756c5194a5e4d AS db
RUN --mount=type=bind,from=gosu,source=/out/gosu,target=/tmp/gosu \
    --mount=type=bind,source=files,target=/tmp/torpress \
    set -eux; \
    install -m 0755 /tmp/gosu /usr/local/bin/gosu; \
    install -D -m 0644 /tmp/torpress/verify-secrets.sh /usr/local/lib/torpress/verify-secrets.sh; \
    install -m 0755 /tmp/torpress/db-start.sh /usr/local/bin/torpress-db
ENTRYPOINT ["/usr/local/bin/torpress-db"]
CMD ["mariadbd"]

FROM wordpress:7.1.5-php8.6-apache@sha256:5138d4ccebff2a2927736e3691c792cb1ae3e3d93a98faaad3126222a9a0cd5e AS wordpress

RUN --mount=type=bind,from=wp_cli,source=/usr/local/bin/wp,target=/tmp/wp \
    --mount=type=bind,source=files,target=/tmp/torpress \
    set -eux; \
    install -m 0755 /tmp/wp /usr/local/bin/wp; \
    install -m 0644 /tmp/torpress/wordpress-config.php /usr/src/wordpress/wp-config.php; \
    install -m 0644 /tmp/torpress/apache-hardening.conf /etc/apache2/conf-available/torpress.conf; \
    install -m 0644 /tmp/torpress/php-hardening.ini /usr/local/etc/php/conf.d/zz-torpress.ini; \
    install -D -m 0644 /tmp/torpress/verify-secrets.sh /usr/local/lib/torpress/verify-secrets.sh; \
    install -m 0644 /tmp/torpress/wordpress-install.php /usr/local/lib/torpress/install.php; \
    install -m 0755 /tmp/torpress/wordpress-start.sh /usr/local/bin/torpress-wordpress; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get purge -y --auto-remove autoconf dpkg-dev file g++ gcc ghostscript libc6-dev make pkg-config re2c; \
    rm -rf /var/lib/apt/lists/*; \
    sed -i 's|DocumentRoot /var/www/html|DocumentRoot /usr/src/wordpress|' /etc/apache2/sites-available/000-default.conf; \
    a2disconf remoteip serve-cgi-bin; \
    for module in autoindex negotiation rewrite status http2 proxy proxy_http proxy_fcgi proxy_uwsgi dav dav_fs cgi cgid userdir usertrack vhost_alias auth_digest md remoteip; do \
        if [ -L "/etc/apache2/mods-enabled/${module}.load" ]; then a2dismod -f "$module"; fi; \
    done; \
    a2enmod headers; \
    a2enconf torpress; \
    rm -f /usr/src/wordpress/wp-config-docker.php; \
    rm -rf /usr/src/wordpress/wp-content/plugins/akismet; \
    rm -f /usr/src/wordpress/wp-content/plugins/hello.php; \
    chown -R root:root /usr/src/wordpress; \
    chmod 0644 /usr/src/wordpress/wp-config.php

WORKDIR /usr/src/wordpress
ENTRYPOINT ["/usr/local/bin/torpress-wordpress"]
CMD ["apache2-foreground"]

FROM debian:trixie-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0 AS tor_key
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    fingerprint=A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89; \
    curl --fail --silent --show-error --location --proto '=https' \
        "https://deb.torproject.org/torproject.org/${fingerprint}.asc" -o /tmp/tor.asc; \
    gpg --batch --with-colons --show-keys /tmp/tor.asc > /tmp/tor.keys; \
    primary_fingerprints="$(awk -F: '$1=="pub" { primary=1; next } primary && $1=="fpr" { print $10; primary=0 }' /tmp/tor.keys)"; \
    test "$primary_fingerprints" = "$fingerprint"; \
    gpg --batch --dearmor --output /tor-archive-keyring.gpg /tmp/tor.asc

FROM debian:trixie-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0 AS tor
ARG TOR_VERSION=0.4.9.17-1~d13.trixie+1
COPY --from=tor_key /tor-archive-keyring.gpg /usr/share/keyrings/tor-archive-keyring.gpg
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    printf '%s\n' 'deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org trixie main' \
        > /etc/apt/sources.list.d/tor.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "tor=${TOR_VERSION}"; \
    rm -rf /var/lib/apt/lists/*; \
    install -d -o debian-tor -g debian-tor -m 0700 /var/lib/tor/hidden_service

COPY --chmod=0644 files/torrc /etc/tor/torrc
COPY --chmod=0755 files/onion-hostname.sh /usr/local/bin/torpress-onion-hostname
USER debian-tor
CMD ["tor", "-f", "/etc/tor/torrc"]
