#!/bin/sh
set -eu

# shellcheck source=files/verify-secrets.sh
. /usr/local/lib/torpress/verify-secrets.sh
torpress_validate_secret db_password
torpress_validate_secret db_root_password
torpress_require_distinct db_password db_root_password

exec /usr/local/bin/docker-entrypoint.sh "$@"
