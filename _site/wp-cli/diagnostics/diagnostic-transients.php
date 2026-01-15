<?php
/**
 * TRANSIENT DIAGNOSTIC SCRIPT
 *
 * Run this via WP-CLI to diagnose transient storage issues
 * Usage: wp eval-file wp-content/themes/robdisbergen/diagnostic-transients.php
 */

echo "=== TRANSIENT DIAGNOSTIC REPORT ===\n";
echo "Generated: " . date('Y-m-d H:i:s') . "\n\n";

// Test 1: Check if transients are being stored
echo "=== TEST 1: Transient Storage Test ===\n";
$test_key = 'diagnostic_test_transient';
$test_value = 'test_data_' . time();
$test_expiry = 300; // 5 minutes

echo "Setting test transient: {$test_key}\n";
$set_result = set_transient($test_key, $test_value, $test_expiry);
echo "set_transient() returned: " . ($set_result ? 'TRUE' : 'FALSE') . "\n";

echo "Immediately retrieving test transient...\n";
$get_result = get_transient($test_key);
echo "get_transient() returned: " . ($get_result !== false ? $get_result : 'FALSE') . "\n";
echo "Values match: " . ($get_result === $test_value ? 'YES ✅' : 'NO ❌') . "\n\n";

// Clean up test transient
delete_transient($test_key);

// Test 2: Check current API properties cache
echo "=== TEST 2: API Properties Cache Status ===\n";
$api_cache = get_transient('api_properties_list');
echo "api_properties_list exists: " . ($api_cache !== false ? 'YES' : 'NO') . "\n";

if ($api_cache !== false) {
    $timeout = get_option('_transient_timeout_api_properties_list');
    $now = time();
    $remaining = $timeout ? ($timeout - $now) : 0;

    echo "Expiration timestamp: " . ($timeout ? date('Y-m-d H:i:s', $timeout) : 'NOT SET') . "\n";
    echo "Current time: " . date('Y-m-d H:i:s', $now) . "\n";
    echo "Seconds remaining: " . $remaining . " (" . round($remaining / 60, 1) . " minutes)\n";
    echo "Data size: " . strlen(serialize($api_cache)) . " bytes\n";

    if (isset($api_cache['resultaten'])) {
        echo "Properties count: " . count($api_cache['resultaten']) . "\n";
    }
} else {
    echo "Cache is currently empty (MISS)\n";
}
echo "\n";

// Test 3: Check object cache status
echo "=== TEST 3: Object Cache Configuration ===\n";
echo "wp_using_ext_object_cache(): " . (wp_using_ext_object_cache() ? 'TRUE (external cache active)' : 'FALSE (database storage)') . "\n";

global $wp_object_cache;
if (is_object($wp_object_cache)) {
    echo "Object cache class: " . get_class($wp_object_cache) . "\n";
}

// Check for LiteSpeed Object Cache
if (defined('LSCWP_V')) {
    echo "LiteSpeed Cache version: " . LSCWP_V . "\n";

    // Check Object Cache setting
    $litespeed_options = get_option('litespeed.conf.cache-object');
    echo "LiteSpeed Object Cache enabled: " . ($litespeed_options ? 'YES' : 'NO') . "\n";
}
echo "\n";

// Test 4: Check transient in database
echo "=== TEST 4: Database Transient Check ===\n";
global $wpdb;

// Check if api_properties_list exists in database
$transient_name = '_transient_api_properties_list';
$timeout_name = '_transient_timeout_api_properties_list';

$transient_value = $wpdb->get_var($wpdb->prepare(
    "SELECT option_value FROM {$wpdb->options} WHERE option_name = %s",
    $transient_name
));

$timeout_value = $wpdb->get_var($wpdb->prepare(
    "SELECT option_value FROM {$wpdb->options} WHERE option_name = %s",
    $timeout_name
));

echo "Database check for '{$transient_name}':\n";
echo "  Exists in database: " . ($transient_value !== null ? 'YES' : 'NO') . "\n";
echo "  Timeout exists: " . ($timeout_value !== null ? 'YES' : 'NO') . "\n";

if ($timeout_value !== null) {
    $now = time();
    $remaining = $timeout_value - $now;
    echo "  Timeout value: " . date('Y-m-d H:i:s', $timeout_value) . "\n";
    echo "  Expired: " . ($remaining < 0 ? 'YES ❌ (expired ' . abs($remaining) . ' seconds ago)' : 'NO ✅') . "\n";
}
echo "\n";

// Test 5: Check for transient cleanup cron
echo "=== TEST 5: Transient Cleanup Cron Jobs ===\n";
$crons = _get_cron_array();
$transient_crons = array();

foreach ($crons as $timestamp => $cron) {
    foreach ($cron as $hook => $details) {
        if (stripos($hook, 'transient') !== false || stripos($hook, 'cache') !== false) {
            $transient_crons[] = array(
                'time' => date('Y-m-d H:i:s', $timestamp),
                'hook' => $hook
            );
        }
    }
}

if (!empty($transient_crons)) {
    echo "Found transient-related cron jobs:\n";
    foreach ($transient_crons as $cron) {
        echo "  [{$cron['time']}] {$cron['hook']}\n";
    }
} else {
    echo "No transient-related cron jobs found\n";
}
echo "\n";

// Test 6: Business hours calculation
echo "=== TEST 6: Business Hours Logic ===\n";
$current_hour = (int) current_time('H');
echo "Current hour: {$current_hour}\n";
echo "Expected cache lifetime: ";

if ($current_hour >= 7 && $current_hour <= 19) {
    echo "10 minutes (business hours)\n";
} else {
    echo "60 minutes (off-hours)\n";
}
echo "\n";

// Test 7: Check recent transient sets
echo "=== TEST 7: Recent Transient Activity ===\n";
$all_transients = $wpdb->get_results(
    "SELECT option_name, option_value as timeout
     FROM {$wpdb->options}
     WHERE option_name LIKE '_transient_timeout_%'
     AND option_value > " . (time() - 3600) . "
     ORDER BY option_value DESC
     LIMIT 20"
);

echo "Transients set in last hour:\n";
foreach ($all_transients as $transient) {
    $name = str_replace('_transient_timeout_', '', $transient->option_name);
    $expiry = date('Y-m-d H:i:s', $transient->timeout);
    echo "  {$name} → expires {$expiry}\n";
}

echo "\n=== DIAGNOSTIC COMPLETE ===\n";
echo "\nRECOMMENDATIONS:\n";

if (wp_using_ext_object_cache()) {
    echo "⚠️  External object cache is active. This may interfere with transient storage.\n";
    echo "   Consider disabling LiteSpeed Object Cache or using persistent object cache.\n";
}

if ($api_cache === false && $transient_value === null) {
    echo "❌ Cache is empty in both memory AND database - something is clearing it.\n";
    echo "   Check for plugins that clear transients (Transients Manager, cache plugins, etc.)\n";
}

if ($api_cache === false && $transient_value !== null && $timeout_value < time()) {
    echo "⚠️  Cache exists in database but is EXPIRED.\n";
    echo "   This is normal - cache should regenerate on next request.\n";
}
