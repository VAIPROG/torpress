<?php

function torpress_secret(string $name): string {
    $value = file_get_contents('/run/torpress/' . $name);
    if ($value === false || rtrim($value, "\r\n") === '') {
        throw new RuntimeException('A required WordPress secret is missing.');
    }
    return rtrim($value, "\r\n");
}

define('DB_NAME', 'wordpress');
define('DB_USER', 'wordpress');
define('DB_PASSWORD', torpress_secret('db_password'));
define('DB_HOST', 'db:3306');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

$torpress_salt = torpress_secret('wordpress_salt');
foreach ([
    'AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY',
    'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT',
] as $torpress_label) {
    define($torpress_label, hash_hmac('sha256', $torpress_label, $torpress_salt));
}
unset($torpress_salt, $torpress_label);

define('WP_DEBUG', false);
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);
define('WP_HTTP_BLOCK_EXTERNAL', true);
define('AUTOMATIC_UPDATER_DISABLED', true);

$table_prefix = 'wp_';
if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}
require_once ABSPATH . 'wp-settings.php';
