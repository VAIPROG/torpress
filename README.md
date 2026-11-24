# Torpress

Torpress helps small media outlets serve WordPress websites through the Tor network. It runs WordPress, MariaDB, and an onion service as separate Docker Compose services. The stack publishes no host ports. Use [Tor Browser](https://www.torproject.org/) to open the onion site.

## Set up a new site

Use Docker with Compose v2, OpenSSL, and Bash. In the repository directory, generate three independent secrets if they do not already exist:

```bash
umask 077
mkdir -p .secrets
for secret in db_password db_root_password wordpress_salt; do
    if [[ ! -e ".secrets/$secret" ]]; then
        openssl rand -hex 32 > ".secrets/$secret"
    fi
done
```

The database and web containers reject missing secrets, common low-entropy patterns, and reuse among the secrets they consume. Keep these files private and retain them with the corresponding database and site backups. Set `TORPRESS_SECRETS_DIR` to use a different directory.

Build the images and start the private services:

```bash
docker compose --profile onion build
docker compose up -d db wordpress
```

Generate the v3 onion identity with Tor's network disabled. The command prints the hostname and saves the private key in the Tor volume. The web container has no access to that volume.

```bash
onion_host=$(docker compose --profile onion run --rm --no-deps tor torpress-onion-hostname)
```

Provision WordPress through the container's CLI. Choose the site title, admin username and email, and enter a unique password from a password manager. The password goes over stdin:

```bash
read -rsp 'WordPress admin password: ' admin_password
printf '\n' >&2
printf '%s' "$admin_password" |
    docker compose exec -T --user www-data wordpress \
        php /usr/local/lib/torpress/install.php "$onion_host" \
        'My Torpress Site' operator operator@example.org
unset admin_password
```

The password must be at least 20 bytes. The web installer is disabled. Once WordPress is installed, enable the onion service:

```bash
docker compose --profile onion up -d tor
printf 'http://%s\n' "$onion_host"
```

## Update or migrate an existing site

- Back up the database, `wp-content`, the Tor identity, and secrets before updating. Treat the onion service key as a private credential.
- For the older single-container Torpress release, create new volumes for the database and content. Import a logical dump of the WordPress application database into the new `wordpress` database. MariaDB creates its own system users from the new secrets. Copy the site's `wp-content` and restore its ownership for `www-data`. The new configuration uses the default `wp_` table prefix. Align the prefix before importing a site that used a custom prefix.
- To keep the old onion address, restore the old hidden-service directory into `/var/lib/tor/hidden_service` in the new Tor volume before generating or starting an identity. Keep its ownership on `debian-tor` and its directory mode at `0700`. Confirm the restored hostname before enabling the onion profile.
- For an existing installation, skip the provisioning script. Use `docker compose exec --user www-data wordpress wp option get home` and `siteurl` to verify both URLs. Use WP-CLI to update them if the hostname changed.
- Core updates come from rebuilding the pinned WordPress image. Review the image digest, rebuild with Tor stopped, start the new WordPress container, and run `docker compose exec --user www-data wordpress wp core update-db` before re-enabling Tor. Update plugins and themes separately from reviewed packages in `wp-content`. The dashboard's file editor and updater are disabled, and WordPress has no direct Internet connection.

## Security checks

The stack uses upstream WordPress, PHP, Apache, MariaDB, and Tor packages. Apache disables unused HTTP/2, proxy, CGI, WebDAV, and rewrite modules, ignores forwarded client IP headers, and blocks TRACE, PHP execution in uploads, and public XML-RPC. PHP display errors and version headers are disabled. MariaDB is reachable only on the backend network, uses a dedicated WordPress user, and disables `LOCAL INFILE`. Ghostscript is omitted, so WordPress does not render PDF thumbnails.

The Apache 2.4.71 update includes the fix for [CVE-2026-119618](https://httpd.apache.org/security/vulnerabilities_24.html#CVE-2026-119618). PHP 8.6.0 includes fixes documented in the [PHP changelog](https://www.php.net/ChangeLog-8.php#8.6.0). Check the [Debian security tracker](https://security-tracker.debian.org/tracker/) for package backports and unresolved issues. Keep the Docker host patched too.

After building, run `bash tests/smoke.sh` to check private provisioning, weak and reused secrets, the Apache policy, WordPress routing, and Tor identity generation. The test uses disposable volumes and keeps Tor networking disabled.
