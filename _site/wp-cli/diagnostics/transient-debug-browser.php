<?php
/**
 * PRODUCTION TRANSIENT DEBUGGER
 *
 * Upload this file to wp-content/ on production server
 * Access via: https://robdisbergen.nl/wp-content/transient-debug-browser.php
 *
 * This will help diagnose why transients fail on production
 */

// Security: Add a secret token to prevent public access
define('DEBUG_SECRET', 'rob2025debug'); // Change this!

if (!isset($_GET['secret']) || $_GET['secret'] !== DEBUG_SECRET) {
    die('Access denied. Add ?secret=rob2025debug to URL');
}

require_once('../wp-load.php');
header('Content-Type: text/html; charset=utf-8');

?>
<!DOCTYPE html>
<html>
<head>
    <title>Production Transient Debugger</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1e1e1e; color: #d4d4d4; }
        .section { background: #252526; padding: 15px; margin: 15px 0; border-left: 3px solid #007acc; }
        .success { color: #4ec9b0; }
        .error { color: #f48771; }
        .warning { color: #dcdcaa; }
        h2 { color: #4ec9b0; margin-top: 0; }
        pre { background: #1e1e1e; padding: 10px; overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; }
        td, th { padding: 8px; text-align: left; border: 1px solid #3c3c3c; }
        th { background: #2d2d30; }
    </style>
</head>
<body>
    <h1>🔍 Production Transient Debugger</h1>
    <p>Generated: <?php echo date('Y-m-d H:i:s'); ?> | Server: <?php echo $_SERVER['SERVER_NAME']; ?></p>

    <?php
    global $wpdb;

    // TEST 1: Basic Transient Functionality
    echo '<div class="section">';
    echo '<h2>TEST 1: Basic Transient Storage</h2>';

    $test_key = 'transient_debug_test_' . time();
    $test_value = 'test_data_' . rand(1000, 9999);

    echo "<p>Setting transient: <code>{$test_key}</code></p>";
    echo "<p>Value: <code>{$test_value}</code></p>";

    $set_result = set_transient($test_key, $test_value, 300);
    echo "<p>set_transient() returned: " . ($set_result ? '<span class="success">TRUE ✅</span>' : '<span class="error">FALSE ❌</span>') . "</p>";

    // Immediately try to get it back
    $get_result = get_transient($test_key);
    $match = ($get_result === $test_value);

    echo "<p>get_transient() returned: <code>" . var_export($get_result, true) . "</code></p>";
    echo "<p>Values match: " . ($match ? '<span class="success">YES ✅</span>' : '<span class="error">NO ❌</span>') . "</p>";

    // Check database directly
    $db_value = $wpdb->get_var($wpdb->prepare(
        "SELECT option_value FROM {$wpdb->options} WHERE option_name = %s",
        '_transient_' . $test_key
    ));

    echo "<p>Database check: " . ($db_value !== null ? '<span class="success">EXISTS in DB ✅</span>' : '<span class="error">NOT in DB ❌</span>') . "</p>";

    if ($db_value !== null) {
        echo "<p>Database value: <code>" . htmlspecialchars(substr($db_value, 0, 100)) . "</code></p>";
    }

    delete_transient($test_key);
    echo '</div>';

    // TEST 2: Database Configuration
    echo '<div class="section">';
    echo '<h2>TEST 2: Database Configuration</h2>';
    echo '<table>';

    $db_vars = [
        'max_allowed_packet',
        'innodb_buffer_pool_size',
        'table_open_cache',
        'tmp_table_size',
        'max_heap_table_size'
    ];

    foreach ($db_vars as $var) {
        $result = $wpdb->get_row("SHOW VARIABLES LIKE '{$var}'");
        if ($result) {
            $value = $result->Value;
            if (strpos($var, 'size') !== false || strpos($var, 'packet') !== false) {
                $mb = round($value / 1024 / 1024, 2);
                $value = number_format($value) . " ({$mb} MB)";
            }
            echo "<tr><td>{$var}</td><td>{$value}</td></tr>";
        }
    }
    echo '</table>';
    echo '</div>';

    // TEST 3: wp_options Table Analysis
    echo '<div class="section">';
    echo '<h2>TEST 3: wp_options Table Analysis</h2>';

    $table_size = $wpdb->get_var("
        SELECT ROUND(((data_length + index_length) / 1024 / 1024), 2)
        FROM information_schema.TABLES
        WHERE table_schema = DATABASE()
        AND table_name = '{$wpdb->options}'
    ");

    $total_options = $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->options}");
    $transient_count = $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name LIKE '_transient_%'");
    $autoload_count = $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->options} WHERE autoload = 'yes'");
    $autoload_size = $wpdb->get_var("SELECT SUM(LENGTH(option_value)) FROM {$wpdb->options} WHERE autoload = 'yes'");

    echo "<table>";
    echo "<tr><td>Table size</td><td>{$table_size} MB</td></tr>";
    echo "<tr><td>Total options</td><td>" . number_format($total_options) . "</td></tr>";
    echo "<tr><td>Transient options</td><td>" . number_format($transient_count) . "</td></tr>";
    echo "<tr><td>Autoload options</td><td>" . number_format($autoload_count) . "</td></tr>";
    echo "<tr><td>Autoload size</td><td>" . round($autoload_size / 1024 / 1024, 2) . " MB</td></tr>";
    echo "</table>";

    if ($autoload_size > 1000000) {
        echo '<p class="warning">⚠️ Autoload size exceeds 1MB - this impacts page load performance</p>';
    }
    echo '</div>';

    // TEST 4: Large Transient Test
    echo '<div class="section">';
    echo '<h2>TEST 4: Large Transient Test</h2>';

    $sizes = [1024, 10240, 102400, 1048576]; // 1KB, 10KB, 100KB, 1MB

    echo '<table>';
    echo '<tr><th>Size</th><th>set_transient()</th><th>get_transient()</th><th>Database</th><th>Status</th></tr>';

    foreach ($sizes as $size) {
        $large_key = 'test_large_' . $size . '_' . time();
        $large_data = str_repeat('X', $size);

        $set = set_transient($large_key, $large_data, 300);
        $get = get_transient($large_key);
        $db = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name = %s",
            '_transient_' . $large_key
        ));

        $status = ($get === $large_data) ? '<span class="success">✅ OK</span>' : '<span class="error">❌ FAIL</span>';

        $size_label = $size >= 1024 ? round($size / 1024, 1) . ' KB' : $size . ' B';

        echo "<tr>";
        echo "<td>{$size_label}</td>";
        echo "<td>" . ($set ? 'TRUE' : 'FALSE') . "</td>";
        echo "<td>" . ($get !== false ? 'SUCCESS' : 'FAIL') . "</td>";
        echo "<td>" . ($db > 0 ? 'YES' : 'NO') . "</td>";
        echo "<td>{$status}</td>";
        echo "</tr>";

        delete_transient($large_key);
    }
    echo '</table>';
    echo '</div>';

    // TEST 5: API Properties Cache
    echo '<div class="section">';
    echo '<h2>TEST 5: API Properties Cache Status</h2>';

    $api_cache = get_transient('api_properties_list');

    if ($api_cache !== false) {
        echo '<p class="success">Cache EXISTS ✅</p>';
        $timeout = get_option('_transient_timeout_api_properties_list');
        $remaining = $timeout ? ($timeout - time()) : 0;
        echo "<p>Expires in: " . round($remaining / 60, 1) . " minutes</p>";

        if (isset($api_cache['resultaten'])) {
            echo "<p>Properties: " . count($api_cache['resultaten']) . "</p>";
        }
    } else {
        echo '<p class="error">Cache is EMPTY ❌</p>';

        // Check database
        $db_exists = $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name = '_transient_api_properties_list'");
        echo "<p>Database: " . ($db_exists > 0 ? 'EXISTS but expired' : 'DOES NOT EXIST') . "</p>";
    }
    echo '</div>';

    // TEST 6: Object Cache Status
    echo '<div class="section">';
    echo '<h2>TEST 6: Object Cache & Plugin Status</h2>';

    echo '<table>';
    echo "<tr><td>wp_using_ext_object_cache()</td><td>" . (wp_using_ext_object_cache() ? 'TRUE' : 'FALSE') . "</td></tr>";

    global $wp_object_cache;
    if (is_object($wp_object_cache)) {
        echo "<tr><td>Object cache class</td><td>" . get_class($wp_object_cache) . "</td></tr>";
    }

    if (defined('LSCWP_V')) {
        echo "<tr><td>LiteSpeed Cache version</td><td>" . LSCWP_V . "</td></tr>";
        $ls_obj_cache = get_option('litespeed.conf.cache-object');
        echo "<tr><td>LiteSpeed Object Cache</td><td>" . ($ls_obj_cache ? 'ENABLED' : 'DISABLED') . "</td></tr>";
    }

    echo '</table>';

    // Check for problematic plugins
    $active_plugins = get_option('active_plugins');
    $cache_plugins = [];

    foreach ($active_plugins as $plugin) {
        if (stripos($plugin, 'cache') !== false ||
            stripos($plugin, 'transient') !== false ||
            stripos($plugin, 'object') !== false ||
            stripos($plugin, 'redis') !== false ||
            stripos($plugin, 'memcache') !== false) {
            $cache_plugins[] = $plugin;
        }
    }

    if (!empty($cache_plugins)) {
        echo '<p class="warning">Cache-related plugins found:</p>';
        echo '<ul>';
        foreach ($cache_plugins as $plugin) {
            echo "<li>{$plugin}</li>";
        }
        echo '</ul>';
    }
    echo '</div>';

    // TEST 7: Server Environment
    echo '<div class="section">';
    echo '<h2>TEST 7: Server Environment</h2>';
    echo '<table>';
    echo "<tr><td>PHP Version</td><td>" . phpversion() . "</td></tr>";
    echo "<tr><td>MySQL Version</td><td>" . $wpdb->db_version() . "</td></tr>";
    echo "<tr><td>WordPress Version</td><td>" . get_bloginfo('version') . "</td></tr>";
    echo "<tr><td>Server Software</td><td>" . $_SERVER['SERVER_SOFTWARE'] . "</td></tr>";
    echo "<tr><td>WP_CACHE</td><td>" . (defined('WP_CACHE') && WP_CACHE ? 'TRUE' : 'FALSE') . "</td></tr>";
    echo "<tr><td>WP_DEBUG</td><td>" . (defined('WP_DEBUG') && WP_DEBUG ? 'TRUE' : 'FALSE') . "</td></tr>";
    echo '</table>';
    echo '</div>';

    // TEST 8: Recent Transients
    echo '<div class="section">';
    echo '<h2>TEST 8: Recent Transient Activity</h2>';

    $recent = $wpdb->get_results("
        SELECT
            REPLACE(option_name, '_transient_timeout_', '') as transient_name,
            option_value as expires_at
        FROM {$wpdb->options}
        WHERE option_name LIKE '_transient_timeout_%'
        ORDER BY option_value DESC
        LIMIT 20
    ");

    if (!empty($recent)) {
        echo '<table>';
        echo '<tr><th>Transient</th><th>Expires At</th><th>Status</th></tr>';

        foreach ($recent as $row) {
            $status = ($row->expires_at > time()) ? '<span class="success">Active</span>' : '<span class="error">Expired</span>';
            $expires = date('Y-m-d H:i:s', $row->expires_at);

            echo "<tr><td>{$row->transient_name}</td><td>{$expires}</td><td>{$status}</td></tr>";
        }
        echo '</table>';
    } else {
        echo '<p class="warning">No transients found in database</p>';
    }
    echo '</div>';

    // RECOMMENDATIONS
    echo '<div class="section">';
    echo '<h2>🎯 Diagnosis & Recommendations</h2>';

    $issues = [];

    if (!$match) {
        $issues[] = "❌ CRITICAL: Transients are completely broken - set works but get fails immediately";
    }

    if ($db_value === null && $set_result === true) {
        $issues[] = "❌ CRITICAL: Transients not being written to database despite set_transient() returning TRUE";
    }

    if (wp_using_ext_object_cache()) {
        $issues[] = "⚠️ External object cache is active - may be misconfigured";
    }

    if ($autoload_size > 2000000) {
        $issues[] = "⚠️ Large autoload size ({$autoload_size} bytes) - consider cleaning up";
    }

    if (empty($issues)) {
        echo '<p class="success">✅ All tests passed! Transients appear to be working correctly.</p>';
    } else {
        echo '<ul>';
        foreach ($issues as $issue) {
            echo "<li>{$issue}</li>";
        }
        echo '</ul>';
    }

    echo '</div>';
    ?>

    <div class="section">
        <h2>📋 Copy This Report</h2>
        <p>Send this full page output to your developer for analysis.</p>
        <p><small>Generated at <?php echo date('Y-m-d H:i:s'); ?> on <?php echo php_uname('n'); ?></small></p>
    </div>

</body>
</html>
