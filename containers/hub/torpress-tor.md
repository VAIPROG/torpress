# Torpress onion service

Tor v3 onion service for a Torpress site. The container runs as an unprivileged
user. Its persistent Tor volume holds the onion identity. Back up that volume
securely to retain the site's onion address.

Use the matching `torpress-wordpress` and `torpress-db` image tags. See the
[Torpress setup guide](https://github.com/VAIPROG/torpress#readme) to generate the
hostname and start the service. [Release notes](https://github.com/VAIPROG/torpress/releases)
include digests for Linux amd64 and arm64.

[Инструкция на русском](https://github.com/VAIPROG/torpress/blob/master/RU.README.md)
