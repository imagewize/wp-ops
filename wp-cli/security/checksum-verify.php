<?php
/**
 * WordPress Checksum Verification Module
 *
 * Verifies WordPress core and plugin files against official checksums
 * to filter out false positives from pattern-based security scanning.
 *
 * @version 1.1.0
 * @date September 10, 2026
 * @see https://github.com/imagewize/wp-ops/issues/224
 *
 * USAGE:
 *   This module is included by scanner-targeted.php and scanner-general.php
 *   It provides functions to verify files against WP core/plugin checksums
 *   and returns a list of files that passed verification (can be skipped in pattern scan).
 *
 * @desc     Checksum verification for reducing false positives in security scans
 * @category security
 * @platform wordpress
 * @runs     local
 * @mutates  false
 * @requires wp-cli (optional, falls back to pattern-only mode if unavailable)
 */

/**
 * Checksum verification result cache
 */
$checksum_cache = [
    'verified_files' => [],    // Files that passed checksum verification
    'failed_files' => [],      // Files that failed checksum verification
    'unverified_files' => [],  // Files that couldn't be verified (no checksum available)
    'wp_cli_available' => null, // Whether WP-CLI is available
    'wp_core_verified' => false, // Whether WP core checksums were verified
    'plugins_verified' => [],   // List of plugins that were verified
];

/**
 * Initialize checksum verification
 *
 * @param string $wp_path Path to WordPress installation
 * @return array Checksum verification results
 */
function init_checksum_verification($wp_path) {
    global $checksum_cache;

    // Reset cache for this scan
    $checksum_cache = [
        'verified_files' => [],
        'failed_files' => [],
        'unverified_files' => [],
        'wp_cli_available' => null,
        'wp_core_verified' => false,
        'plugins_verified' => [],
    ];

    // Check if WP-CLI is available
    $checksum_cache['wp_cli_available'] = is_wp_cli_available();

    if (!$checksum_cache['wp_cli_available']) {
        output('WP-CLI not available - checksum verification disabled (pattern-only mode)', 'yellow');
        return $checksum_cache;
    }

    output('WP-CLI available - running checksum verification...', 'green');

    // Verify WordPress core
    verify_wp_core_checksums($wp_path);

    // Verify plugins
    verify_plugin_checksums($wp_path);

    return $checksum_cache;
}

/**
 * Check if WP-CLI is available
 *
 * @return bool True if WP-CLI is available
 */
function is_wp_cli_available() {
    // Check if WP-CLI is in PATH
    $wp_cli_path = trim(shell_exec('which wp 2>/dev/null'));
    if (!empty($wp_cli_path) && is_executable($wp_cli_path)) {
        return true;
    }

    // Check if we're running via WP-CLI (wp eval-file)
    if (defined('WP_CLI') && WP_CLI) {
        return true;
    }

    // Check for common WP-CLI phar locations
    $common_paths = [
        '/usr/local/bin/wp',
        '/usr/bin/wp',
        'wp',
        dirname(__FILE__, 4) . '/wp-cli.phar',
    ];

    foreach ($common_paths as $path) {
        if (file_exists($path) && is_executable($path)) {
            return true;
        }
    }

    return false;
}

/**
 * Run a shell command with stdout and stderr captured separately.
 *
 * WP-CLI writes "Success:" lines to stdout but "Warning:"/"Error:" lines to
 * stderr (see WP_CLI\Loggers\Regular). Merging both streams with `2>&1`
 * makes it impossible to tell a clean JSON success payload apart from
 * warning text without fragile string surgery, so this keeps them apart.
 *
 * @param string $cmd Command to run (executed in the current working directory)
 * @return array{0: string, 1: string} [$stdout, $stderr]
 */
function run_command_capture($cmd) {
    $descriptors = [
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];

    $process = proc_open($cmd, $descriptors, $pipes);
    if (!is_resource($process)) {
        return ['', ''];
    }

    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($process);

    return [(string) $stdout, (string) $stderr];
}

/**
 * Verify WordPress core checksums using WP-CLI
 *
 * @param string $wp_path Path to WordPress installation
 * @return void Populates global $checksum_cache
 */
function verify_wp_core_checksums($wp_path) {
    global $checksum_cache;

    $old_dir = getcwd();
    chdir($wp_path);

    // `wp core verify-checksums` has no --format option (unlike `wp plugin
    // verify-checksums`) - passing --format=json makes WP-CLI reject the
    // command with "Parameter errors: unknown --format parameter" before it
    // runs at all. It only ever prints plain-text Warning/Success/Error
    // lines, so that's what gets parsed here.
    list($stdout, $stderr) = run_command_capture('wp core verify-checksums');

    chdir($old_dir);

    if (strpos($stdout, 'Success: WordPress installation verifies against checksums.') !== false) {
        $checksum_cache['wp_core_verified'] = true;
        output('WordPress core checksums: VERIFIED', 'green');

        // A clean run doesn't give us an explicit file list, but it does
        // mean every core file matched - mark them all verified directly.
        mark_core_files_verified($wp_path);
        return;
    }

    // WP-CLI can't reach the WordPress.org checksums API (no egress from
    // this host, a dev/edge version with no published checksums, etc.) and
    // never compared a single file - that's "couldn't check", not evidence
    // of tampering, so don't report it as a FAILED/compromised core.
    if (strpos($stderr, "Couldn't get checksums from WordPress.org") !== false) {
        output('WordPress core checksums: UNABLE TO VERIFY (could not fetch checksums from wordpress.org - check network/egress)', 'yellow');
        return;
    }

    // Only a real per-file mismatch (a "Warning: ..." line) counts as an
    // actual checksum failure; any other stderr text without one of those
    // is an environment/version problem, not a compromise signal.
    if (strpos($stderr, 'Warning:') !== false) {
        output('WordPress core checksums: FAILED', 'red');
        parse_core_checksum_output($stderr, $wp_path);
        return;
    }

    output('WordPress core checksums: UNABLE TO VERIFY (dev/edge version, no network access, or non-standard WP layout?)', 'yellow');
}

/**
 * Mark all WordPress core files as verified
 *
 * @param string $wp_path Path to WordPress installation
 * @return void
 */
function mark_core_files_verified($wp_path) {
    global $checksum_cache;

    // Define WordPress core directories
    $core_dirs = [
        '', // root
        'wp-admin',
        'wp-includes',
    ];

    $core_files = [
        'wp-activate.php',
        'wp-blog-header.php',
        'wp-comments-post.php',
        'wp-config-sample.php',
        'wp-cron.php',
        'wp-links-opml.php',
        'wp-load.php',
        'wp-login.php',
        'wp-mail.php',
        'wp-settings.php',
        'wp-signup.php',
        'wp-trackback.php',
        'xmlrpc.php',
        'index.php',
        'license.txt',
        'readme.html',
        'wp-config.php',
    ];

    foreach ($core_dirs as $dir) {
        $dir_path = $wp_path . '/' . $dir;
        if (is_dir($dir_path)) {
            $iterator = new RecursiveIteratorIterator(
                new RecursiveDirectoryIterator($dir_path, RecursiveDirectoryIterator::SKIP_DOTS),
                RecursiveIteratorIterator::SELF_FIRST
            );

            foreach ($iterator as $file) {
                if ($file->isFile()) {
                    $filepath = $file->getPathname();
                    $checksum_cache['verified_files'][$filepath] = 'core';
                }
            }
        }
    }

    // Also mark root-level core files
    foreach ($core_files as $file) {
        $filepath = $wp_path . '/' . $file;
        if (file_exists($filepath)) {
            $checksum_cache['verified_files'][$filepath] = 'core';
        }
    }
}

/**
 * Parse wp core verify-checksums text output (stderr)
 *
 * @param string $output stderr captured from `wp core verify-checksums`
 * @param string $wp_path Path to WordPress installation
 * @return void
 */
function parse_core_checksum_output($output, $wp_path) {
    global $checksum_cache;

    foreach (explode("\n", $output) as $line) {
        $line = trim($line);

        // WP-CLI reports one line per problem file, e.g.:
        //   Warning: File doesn't verify against checksum: wp-includes/version.php
        //   Warning: File doesn't exist: wp-includes/some-deleted-file.php
        //   Warning: File should not exist: wp-includes/shell.php
        // The message text never itself contains ": ", so splitting on the
        // last "message: path" boundary isolates the file path regardless of
        // which of the three messages WP-CLI used.
        if (preg_match('/^(?:Warning|Error):\s+(.+):\s+(\S+)$/', $line, $matches)) {
            $reason = $matches[1];
            $file = $matches[2];
            $filepath = $wp_path . '/' . ltrim($file, '/');
            if (file_exists($filepath)) {
                $checksum_cache['failed_files'][$filepath] = [
                    'type' => 'core',
                    'reason' => $reason,
                    'severity' => 'CRITICAL',
                ];
            }
        }
    }
}

/**
 * Verify plugin checksums using WP-CLI
 *
 * @param string $wp_path Path to WordPress installation
 * @return void Populates global $checksum_cache
 */
function verify_plugin_checksums($wp_path) {
    global $checksum_cache;

    $old_dir = getcwd();
    chdir($wp_path);
    $plugins_output = shell_exec('wp plugin list --field=name 2>/dev/null');
    chdir($old_dir);

    // Some PHP/WP-CLI combinations (an old bundled dependency hitting a
    // newer PHP's deprecation notices, for example) print `Deprecated: ...`
    // straight to stdout instead of stderr, landing it right in this
    // newline-per-slug list. Keep only lines that actually look like a
    // plugin directory slug so that noise can't masquerade as a plugin.
    $plugin_slugs = array_values(array_filter(
        array_map('trim', explode("\n", (string) $plugins_output)),
        fn($line) => preg_match('/^[A-Za-z0-9_.\-]+$/', $line) === 1
    ));

    if (empty($plugin_slugs)) {
        output('Unable to list plugins for checksum verification', 'yellow');
        return;
    }

    $old_dir = getcwd();
    chdir($wp_path);
    // One WP-CLI process for every installed plugin via --all, instead of
    // one process per plugin - a site with 40 plugins would otherwise spawn
    // 40+ PHP/WP-CLI bootstraps just for this step.
    list($stdout, $stderr) = run_command_capture('wp plugin verify-checksums --all --format=json');
    chdir($old_dir);

    // Plugins WP-CLI couldn't get checksums for (custom/premium, not on
    // wordpress.org, or a version mismatch) are reported as warnings on
    // stderr, not as errors - track them so their files stay unverified
    // (still pattern-scanned) instead of being wrongly marked as clean.
    $skipped_slugs = [];
    foreach (explode("\n", $stderr) as $line) {
        if (preg_match('/plugin ([^\s,]+), skipping\.?$/i', trim($line), $matches)) {
            $skipped_slugs[$matches[1]] = true;
            output("Plugin '{$matches[1]}' - checksums not available (not from wordpress.org, or version mismatch)", 'yellow');
        }
    }

    // On success (no failing plugin) `--format=json` prints nothing at all -
    // the only output is a plain "Success: ..." summary line. When there ARE
    // failures, the JSON error array ([{"plugin_name":...,"file":...,
    // "message":...}, ...]) is what gets printed - located by its outermost
    // brackets rather than assumed to be the whole of stdout, since some
    // PHP/WP-CLI combinations print stray notices to stdout ahead of it.
    $failed_slugs = [];
    $json_start = strpos($stdout, '[');
    $json_end = strrpos($stdout, ']');
    if ($json_start !== false && $json_end !== false && $json_end > $json_start) {
        $errors = json_decode(substr($stdout, $json_start, $json_end - $json_start + 1), true);
        if (is_array($errors)) {
            foreach ($errors as $error) {
                if (empty($error['plugin_name']) || empty($error['file'])) {
                    continue;
                }

                $plugin_slug = $error['plugin_name'];
                $failed_slugs[$plugin_slug] = true;

                $filepath = $wp_path . '/wp-content/plugins/' . $plugin_slug . '/' . ltrim($error['file'], '/');
                if (!file_exists($filepath)) {
                    // Single-file plugins (e.g. Hello Dolly) live directly in
                    // the plugins directory, not their own subfolder.
                    $flat_path = $wp_path . '/wp-content/plugins/' . ltrim($error['file'], '/');
                    if (file_exists($flat_path)) {
                        $filepath = $flat_path;
                    }
                }

                if (file_exists($filepath)) {
                    $checksum_cache['failed_files'][$filepath] = [
                        'type' => 'plugin:' . $plugin_slug,
                        'reason' => $error['message'] ?? 'Checksum mismatch',
                        'severity' => 'CRITICAL',
                    ];
                }
            }
        }
    }

    foreach ($plugin_slugs as $plugin_slug) {
        if (isset($failed_slugs[$plugin_slug])) {
            $checksum_cache['plugins_verified'][$plugin_slug] = false;
            continue;
        }

        if (isset($skipped_slugs[$plugin_slug])) {
            continue;
        }

        $checksum_cache['plugins_verified'][$plugin_slug] = true;
        mark_plugin_files_verified($wp_path, $plugin_slug);
    }
}

/**
 * Mark all files in a plugin directory as verified
 *
 * @param string $wp_path Path to WordPress installation
 * @param string $plugin_slug Plugin slug
 * @return void
 */
function mark_plugin_files_verified($wp_path, $plugin_slug) {
    global $checksum_cache;

    $plugin_dir = $wp_path . '/wp-content/plugins/' . $plugin_slug;

    if (!is_dir($plugin_dir)) {
        return;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($plugin_dir, RecursiveDirectoryIterator::SKIP_DOTS),
        RecursiveIteratorIterator::SELF_FIRST
    );

    foreach ($iterator as $file) {
        if ($file->isFile()) {
            $filepath = $file->getPathname();
            $checksum_cache['verified_files'][$filepath] = 'plugin:' . $plugin_slug;
        }
    }
}

/**
 * Check if a file passed checksum verification
 *
 * @param string $filepath Full path to the file
 * @return string|null Returns 'core', 'plugin:slug', or null if not verified
 */
function is_file_verified($filepath) {
    global $checksum_cache;
    return $checksum_cache['verified_files'][$filepath] ?? null;
}

/**
 * Check if a file failed checksum verification
 *
 * @param string $filepath Full path to the file
 * @return array|null Returns failure info or null if not failed
 */
function is_file_failed_checksum($filepath) {
    global $checksum_cache;
    return $checksum_cache['failed_files'][$filepath] ?? null;
}

/**
 * Get checksum verification summary
 *
 * @return array Summary statistics
 */
function get_checksum_summary() {
    global $checksum_cache;

    return [
        'wp_cli_available' => $checksum_cache['wp_cli_available'],
        'wp_core_verified' => $checksum_cache['wp_core_verified'],
        'plugins_verified' => $checksum_cache['plugins_verified'],
        'verified_count' => count($checksum_cache['verified_files']),
        'failed_count' => count($checksum_cache['failed_files']),
    ];
}

/**
 * Output checksum verification results
 *
 * @return void
 */
function output_checksum_results() {
    global $checksum_cache;

    $summary = get_checksum_summary();

    if (!$summary['wp_cli_available']) {
        output('Checksum verification: SKIPPED (WP-CLI not available)', 'yellow');
        return;
    }

    output('', 'white');
    output('============================================', 'cyan');
    output('  CHECKSUM VERIFICATION RESULTS', 'cyan');
    output('============================================', 'cyan');
    output('', 'white');

    output('WordPress Core: ' . ($summary['wp_core_verified'] ? 'VERIFIED' : 'NOT VERIFIED'),
           $summary['wp_core_verified'] ? 'green' : 'red');

    output('Plugins Verified: ' . count($summary['plugins_verified']), 'white');

    if (!empty($summary['plugins_verified'])) {
        foreach ($summary['plugins_verified'] as $plugin => $verified) {
            output('  - ' . $plugin . ': ' . ($verified ? 'VERIFIED' : 'FAILED'),
                   $verified ? 'green' : 'red');
        }
    }

    output('Files Verified: ' . $summary['verified_count'], 'green');
    output('Files Failed: ' . $summary['failed_count'],
           $summary['failed_count'] > 0 ? 'red' : 'green');

    // List failed checksum files (high priority!)
    if (!empty($checksum_cache['failed_files'])) {
        output('', 'white');
        output('============================================', 'red');
        output('  CHECKSUM FAILURES (HIGH PRIORITY)', 'red');
        output('============================================', 'red');
        output('', 'white');
        output('These files have been modified from official releases!', 'red');
        output('Investigate immediately - these are strong compromise indicators.', 'red');
        output('', 'white');

        foreach ($checksum_cache['failed_files'] as $filepath => $info) {
            output('FILE: ' . $filepath, 'red');
            output('  Type: ' . $info['type'], 'white');
            output('  Reason: ' . $info['reason'], 'yellow');
            output('  Severity: ' . $info['severity'], 'red');
            output('', 'white');
        }
    }

    output('', 'white');
}

/**
 * Filter files based on checksum verification
 *
 * @param array $files Array of file paths to scan
 * @param string $wp_path WordPress root path
 * @return array Filtered files (files that should still be pattern-scanned)
 */
function filter_files_by_checksum($files, $wp_path) {
    global $checksum_cache;

    if (!$checksum_cache['wp_cli_available']) {
        // No checksum verification available, scan all files
        return $files;
    }

    $filtered = [];
    $skipped_verified = [];
    $skipped_failed = [];

    foreach ($files as $file) {
        // Always scan files that failed checksum
        if (isset($checksum_cache['failed_files'][$file])) {
            $filtered[] = $file;
            continue;
        }

        // Skip files that passed checksum verification
        if (isset($checksum_cache['verified_files'][$file])) {
            $skipped_verified[] = $file;
            continue;
        }

        // Scan files that couldn't be verified (uploads, themes, mu-plugins, etc.)
        $filtered[] = $file;
    }

    // Report how many files were skipped due to checksum verification
    if (count($skipped_verified) > 0) {
        output('', 'white');
        output('Skipping ' . count($skipped_verified) . ' verified core/plugin files (checksum passed)', 'green');
    }

    return $filtered;
}
