#!/bin/sh
set -eu

# shellcheck source=files/verify-secrets.sh
. /usr/local/lib/torpress/verify-secrets.sh
torpress_validate_secret db_password
torpress_validate_secret wordpress_salt
torpress_require_distinct db_password wordpress_salt

# Compose mounts host files. Apache workers get read-only copies on tmpfs.
install -d -m 0750 -o root -g www-data /run/torpress
install -m 0660 -o root -g www-data /dev/null /run/torpress/install.lock
for secret in db_password wordpress_salt; do
    install -m 0440 -o root -g www-data "/run/secrets/$secret" "/run/torpress/$secret"
done

install -d -m 0750 -o www-data -g www-data /usr/src/wordpress/wp-content
exec "$@"
