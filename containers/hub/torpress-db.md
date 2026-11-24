# Torpress MariaDB

MariaDB for Torpress. The startup script validates separate database and root
secrets. The Torpress Compose stack limits database access to the private
backend network and disables `LOCAL INFILE`.

Use the matching `torpress-wordpress` and `torpress-tor` image tags. See the
[Torpress setup guide](https://github.com/VAIPROG/torpress#readme) for secrets,
backups, and migration. [Release notes](https://github.com/VAIPROG/torpress/releases)
include digests for Linux amd64 and arm64.
