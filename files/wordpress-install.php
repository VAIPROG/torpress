<?php

if (PHP_SAPI !== 'cli' || $argc !== 5) {
    fwrite(STDERR, "Usage: install.php ONION_HOST TITLE ADMIN_USER ADMIN_EMAIL (password on stdin)\n");
    exit(2);
}

[, $hostname, $title, $username, $email] = $argv;
if (!preg_match('/\A[a-z2-7]{56}\.onion\z/', $hostname)) {
    fwrite(STDERR, "Provide a v3 onion hostname.\n");
    exit(2);
}
$input = stream_get_contents(STDIN, 1026);
$password = rtrim($input, "\r\n");
if (strlen($input) > 1025 || strlen($password) < 20 || strlen($password) > 1024 ||
    strlen(count_chars($password, 3)) < 8 || preg_match('/\A(.{1,32})\1+\z/s', $password) ||
    str_contains($password, "\0") || str_contains($password, "\n") || str_contains($password, "\r")) {
    fwrite(STDERR, "Provide an admin password of 20 to 1024 bytes on stdin.\n");
    exit(2);
}

$lock = fopen('/run/torpress/install.lock', 'r+');
if ($lock === false || !flock($lock, LOCK_EX)) {
    fwrite(STDERR, "Unable to lock WordPress provisioning.\n");
    exit(1);
}

$site_url = 'http://' . $hostname;
define('WP_SITEURL', $site_url);
define('WP_INSTALLING', true);
require '/usr/src/wordpress/wp-load.php';
require_once ABSPATH . 'wp-admin/includes/upgrade.php';

if (is_blog_installed()) {
    fwrite(STDERR, "WordPress is already installed. Use WP-CLI to manage existing users.\n");
    exit(1);
}

if ($title === '' || !validate_username($username) || !is_email($email)) {
    fwrite(STDERR, "Provide a site title, a valid admin username, and an email address.\n");
    exit(2);
}
if (hash_equals(DB_PASSWORD, $password)) {
    fwrite(STDERR, "The admin password must differ from the database password.\n");
    exit(2);
}

// Provision privately and leave publishing to the operator.
add_filter('pre_wp_mail', '__return_true');
wp_install($title, $username, $email, false, '', $password);
update_option('home', $site_url);
update_option('siteurl', $site_url);
fwrite(STDOUT, "WordPress installed.\n");
