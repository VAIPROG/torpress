#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
umask 077
probe="$(mktemp -d)"
project="torpress-smoke-$(openssl rand -hex 6)"
export TORPRESS_SECRETS_DIR="$probe/secrets"
mkdir "$TORPRESS_SECRETS_DIR" "$probe/weak"
for secret in db_password db_root_password wordpress_salt; do
    openssl rand -hex 32 > "$TORPRESS_SECRETS_DIR/$secret"
done

cat > "$probe/override.yaml" <<'YAML'
services:
  db:
    image: torpress-db
    restart: "no"
  wordpress:
    image: torpress-wordpress
    restart: "no"
  tor:
    image: torpress-tor
    command: ["tor", "-f", "/etc/tor/torrc", "--DisableNetwork", "1"]
    restart: "no"
YAML
compose=(docker compose --project-name "$project" --profile onion -f compose.yaml -f "$probe/override.yaml")

cleanup() {
    "${compose[@]}" down --volumes --remove-orphans >/dev/null
    rm -rf -- "$probe"
}
trap cleanup EXIT

reject_secret() {
    local service=$1 diagnostic=$2
    shift 2
    if TORPRESS_SECRETS_DIR="$probe/weak" "${compose[@]}" run --rm --no-deps --pull never "$service" "$@" >"$probe/rejection" 2>&1; then
        printf 'Expected %s to refuse unsafe credentials.\n' "$service" >&2
        exit 1
    fi
    if ! grep -Fq -- "$diagnostic" "$probe/rejection"; then
        cat "$probe/rejection" >&2
        exit 1
    fi
}

cp "$TORPRESS_SECRETS_DIR"/* "$probe/weak/"
printf '%064d\n' 0 > "$probe/weak/db_password"
reject_secret db 'Missing or weak secret: db_password' --version
cp "$TORPRESS_SECRETS_DIR/db_password" "$probe/weak/db_password"
cp "$TORPRESS_SECRETS_DIR/db_password" "$probe/weak/db_root_password"
reject_secret db 'Secrets db_password and db_root_password must be different' --version
printf '%s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' > "$probe/weak/wordpress_salt"
reject_secret wordpress 'Missing or weak secret: wordpress_salt' php --version
cp "$TORPRESS_SECRETS_DIR/db_password" "$probe/weak/wordpress_salt"
reject_secret wordpress 'Secrets db_password and wordpress_salt must be different' php --version

"${compose[@]}" up -d --no-build --pull never db wordpress
wordpress() { "${compose[@]}" exec -T wordpress "$@"; }
wp() { "${compose[@]}" exec -T --user www-data wordpress wp "$@"; }

host=$("${compose[@]}" run --rm --no-deps --pull never tor torpress-onion-hostname)
[[ $host =~ ^[a-z2-7]{56}\.onion$ ]]
http_code() { wordpress curl -sS -o /dev/null -w '%{http_code}' -H "Host: $host" "http://127.0.0.1$1"; }

[[ $(http_code /wp-admin/install.php) == 403 ]]
[[ $(http_code /wp-admin/setup-config.php) == 403 ]]
if wp core is-installed --url=http://127.0.0.1; then
    printf '%s\n' 'WordPress must begin uninstalled.' >&2
    exit 1
fi

if printf '%s' 'abcdefghabcdefghabcdefgh' | "${compose[@]}" exec -T --user www-data wordpress \
    php /usr/local/lib/torpress/install.php "$host" 'Torpress test' operator operator@example.invalid >"$probe/rejection" 2>&1; then
    printf '%s\n' 'Expected the installer to refuse a weak admin password.' >&2
    exit 1
fi
grep -Fq 'Provide an admin password' "$probe/rejection"

install_output=$(openssl rand -hex 32 | "${compose[@]}" exec -T --user www-data wordpress \
    php /usr/local/lib/torpress/install.php "$host" 'Torpress test' operator operator@example.invalid 2>&1)
if [[ $install_output != "WordPress installed." ]]; then
    printf '%s\n' "$install_output" >&2
    exit 1
fi
wp core is-installed
[[ $(wp option get home) == "http://$host" ]]
[[ $(wp option get siteurl) == "http://$host" ]]
[[ $(http_code /) == 200 ]]
[[ $(http_code /wp-config.php) == 403 ]]
[[ $(http_code /xmlrpc.php) == 403 ]]
[[ $(wordpress curl -sS -X TRACE -o /dev/null -w '%{http_code}' http://127.0.0.1/) == 405 ]]
headers=$(wordpress curl -sSI http://127.0.0.1/)
if grep -iq '^X-Powered-By:' <<< "$headers"; then
    printf '%s\n' 'PHP exposes its version in response headers.' >&2
    exit 1
fi
grep -iq '^X-Content-Type-Options: nosniff' <<< "$headers"
# PHP expands $wpdb inside WP-CLI.
# shellcheck disable=SC2016
[[ $(wp eval 'global $wpdb; echo $wpdb->get_var("SELECT @@local_infile");') == 0 ]]
wp eval 'exit(!DISALLOW_FILE_EDIT || !DISALLOW_FILE_MODS || !WP_HTTP_BLOCK_EXTERNAL || WP_DEBUG);'

"${compose[@]}" exec -T --user www-data wordpress sh -eu -c '
    test ! -w wp-includes/version.php
    test ! -r /run/secrets/db_root_password
    mkdir -p wp-content/uploads
    printf "inert\n" > wp-content/uploads/fixture.php
    printf "inert\n" > wp-content/uploads/fixture.txt
'
[[ $(http_code /wp-content/uploads/fixture.php) == 403 ]]
[[ $(http_code /wp-content/uploads/fixture.txt) == 200 ]]
wp option update permalink_structure '/%postname%/'
wp post create --post_title='Smoke case' --post_name=smoke-case --post_status=publish --post_content='Ready'
[[ $(http_code /smoke-case/) == 200 ]]

wordpress apache2ctl -t
modules=$(wordpress apache2ctl -M)
if grep -Eq '(autoindex|cgi|cgid|dav|dav_fs|http2|md|negotiation|proxy|remoteip|rewrite|status|vhost_alias)_module' <<< "$modules"; then
    printf '%s\n' 'An unnecessary Apache module is enabled.' >&2
    exit 1
fi

"${compose[@]}" up -d --no-build --pull never tor
"${compose[@]}" exec -T tor tor -f /etc/tor/torrc --verify-config
[[ $("${compose[@]}" exec -T tor cat /var/lib/tor/hidden_service/hostname) == "$host" ]]
"${compose[@]}" logs --no-log-prefix tor | grep -F 'DisableNetwork is set' >/dev/null
for service in db wordpress tor; do
    container=$("${compose[@]}" ps -q "$service")
    [[ $(docker inspect --format '{{len .HostConfig.PortBindings}}' "$container") == 0 ]]
done
printf '%s\n' 'Torpress smoke checks passed without publishing an onion service.'
