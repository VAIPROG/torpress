# Torpress WordPress

WordPress with PHP and Apache for a site served through a Tor v3 onion address.
Torpress disables web-based setup, XML-RPC, and PHP execution in uploads. The
Compose stack keeps WordPress on private networks and provisions the site
through its container CLI.

Use the matching `torpress-db` and `torpress-tor` image tags. The
[Torpress setup guide](https://github.com/VAIPROG/torpress#readme) covers secrets,
installation, and upgrades. [Release notes](https://github.com/VAIPROG/torpress/releases)
include digests for Linux amd64 and arm64.
