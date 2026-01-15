<?php
/**
 * WordPress Security & Malware Scanner
 *
 * Enhanced scanner specifically tailored for Rob Disbergen WordPress site.
 * Includes checks for common malware patterns plus specific concerns from
 * the November 2025 security investigation.
 *
 * @version 1.0.0
 * @date November 5, 2025
 * @see docs/LOADING-ISSUES.md for context
 *
 * SECURITY NOTES:
 * - This script should be deleted after use or secured with authentication
 * - Never leave this file accessible on production without protection
 * - Run via WP-CLI or secure it with IP whitelist
 *
 * USAGE:
 *
 * Via WP-CLI (recommended):
 *   wp eval-file wp-content/themes/robdisbergen/security-scanner.php
 *
 * Via Browser (secure with IP check first):
 *   https://yoursite.com/wp-content/themes/robdisbergen/security-scanner.php
 *
 * Via Command Line:
 *   php wp-content/themes/robdisbergen/security-scanner.php
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

// Security: Restrict access by IP (CHANGE THIS TO YOUR IP or use WP-CLI)
// Comment out these lines when using WP-CLI
if (php_sapi_name() !== 'cli') {
    $allowed_ips = [
        '127.0.0.1',           // Localhost
        '::1',                  // IPv6 localhost
        // 'YOUR.IP.ADDRESS.HERE', // Add your IP here
    ];

    $client_ip = $_SERVER['REMOTE_ADDR'] ?? '';
    if (!in_array($client_ip, $allowed_ips)) {
        http_response_code(403);
        exit('Access Denied. This security scanner is restricted.');
    }
}

// Scan configuration
// Allow custom path from command line or WP-CLI
// Usage: php security-scanner.php /path/to/scan
//        wp eval-file security-scanner.php --path=/path/to/scan
$custom_path = null;

// Detect path from various sources
if (php_sapi_name() === 'cli') {
    // Check for --path= flag (works with WP-CLI)
    if (isset($_SERVER['argv'])) {
        foreach ($_SERVER['argv'] as $arg) {
            if (strpos($arg, '--path=') === 0) {
                $custom_path = substr($arg, 7); // Remove '--path='
                break;
            }
        }
    }

    // Check for direct path argument (standard CLI)
    if (!$custom_path && isset($argv[1]) && strpos($argv[1], '--') !== 0) {
        $custom_path = $argv[1];
    }

    // Expand ~ to home directory
    if ($custom_path && substr($custom_path, 0, 2) === '~/') {
        $custom_path = $_SERVER['HOME'] . substr($custom_path, 1);
    }

    // Validate directory exists
    if ($custom_path && !is_dir($custom_path)) {
        echo "Error: Directory not found: {$custom_path}\n";
        exit(1);
    }
}

// Fallback to WordPress root if available
if (!$custom_path && defined('ABSPATH')) {
    $custom_path = ABSPATH;
}

$config = [
    'start_path' => $custom_path ?: dirname(__FILE__, 4), // WordPress root or custom path
    'exclude_dirs' => [
        'node_modules',
        '.git',
        'vendor',
        'wp-content/uploads/cache',
        'wp-content/cache',
    ],
    'file_extensions' => ['php', 'js', 'txt', 'htm', 'html'],
    'max_execution_time' => 300,
    'max_file_size' => 5 * 1024 * 1024, // 5MB - skip files larger than this
];

// Set execution limits
ini_set('max_execution_time', $config['max_execution_time']);
set_time_limit($config['max_execution_time']);
ini_set('display_errors', '1');

// ============================================================================
// MALWARE PATTERNS - Based on LOADING-ISSUES.md Investigation
// ============================================================================

/**
 * Pattern categories for malware detection
 */
$patterns = [
    // Facebook Redirect Patterns (from November 2025 investigation)
    'facebook_redirect' => [
        'name' => 'Facebook Redirect Attempts',
        'description' => 'Patterns that could redirect to facebook.com',
        'patterns' => [
            '/window\.location\s*=.*facebook\.com/i',
            '/window\.location\.href\s*=.*facebook\.com/i',
            '/location\.replace.*facebook\.com/i',
            '/location\.assign.*facebook\.com/i',
            '/header\s*\(\s*["\']location:.*facebook\.com/i',
            '/wp_redirect.*facebook\.com/i',
            '/wp_safe_redirect.*facebook\.com/i',
            '/<meta[^>]*http-equiv=["\']refresh["\'][^>]*facebook\.com/i',
        ],
        'severity' => 'CRITICAL',
    ],

    // Generic Redirect Patterns
    'suspicious_redirects' => [
        'name' => 'Suspicious Redirect Code',
        'description' => 'Obfuscated or suspicious redirect patterns',
        'patterns' => [
            '/window\.location\s*=\s*atob\s*\(/i',           // Base64 encoded redirect
            '/window\.location\s*=\s*String\.fromCharCode/i', // Character code redirect
            '/location\.href\s*=\s*atob\s*\(/i',
            '/header\s*\(\s*["\']location:\s*["\']\s*\.\s*\$/i', // Dynamic header
            '/<script[^>]*src=["\'][^"\']*facebook\.com[^"\']*["\'][^>]*>/i', // External FB script
        ],
        'severity' => 'HIGH',
    ],

    // Common PHP Malware Patterns
    'php_malware' => [
        'name' => 'PHP Malware Patterns',
        'description' => 'Common PHP malware and backdoor patterns',
        'patterns' => [
            '/eval\s*\(\s*base64_decode/i',                 // Obfuscated eval
            '/eval\s*\(\s*gzinflate/i',                     // Compressed eval
            '/eval\s*\(\s*gzuncompress/i',                  // Compressed eval
            '/eval\s*\(\s*str_rot13/i',                     // ROT13 eval
            '/assert\s*\(\s*base64_decode/i',               // Assert backdoor
            '/preg_replace\s*\(.*\/e/i',                    // Preg_replace eval
            '/system\s*\(\s*\$_(GET|POST|REQUEST)/i',       // Direct system calls
            '/exec\s*\(\s*\$_(GET|POST|REQUEST)/i',         // Direct exec
            '/passthru\s*\(\s*\$_(GET|POST|REQUEST)/i',     // Direct passthru
            '/shell_exec\s*\(\s*\$_(GET|POST|REQUEST)/i',   // Direct shell_exec
            '/popen\s*\(\s*\$_(GET|POST|REQUEST)/i',        // Direct popen
            '/proc_open\s*\(\s*\$_(GET|POST|REQUEST)/i',    // Direct proc_open
            '/file_get_contents\s*\(\s*["\']php:\/\/input/i', // PHP input stream
            '/\$_(GET|POST|REQUEST|COOKIE|SERVER)\[.*\]\s*\(/i', // Dynamic function calls
            '/create_function\s*\(.*\$_(GET|POST|REQUEST)/i',  // Create_function exploit
            '/ob_start\s*\(\s*["\']ob_gzhandler/i',         // Output buffer tricks
        ],
        'severity' => 'CRITICAL',
    ],

    // File Download Vulnerability (like the one found in download.php)
    'file_disclosure' => [
        'name' => 'Arbitrary File Download/Disclosure',
        'description' => 'Patterns that could allow unauthorized file access',
        'patterns' => [
            '/readfile\s*\(\s*\$_(GET|POST|REQUEST)/i',
            '/file_get_contents\s*\(\s*\$_(GET|POST|REQUEST)/i',
            '/fopen\s*\(\s*\$_(GET|POST|REQUEST)/i',
            '/include\s*\(\s*\$_(GET|POST|REQUEST)/i',
            '/include_once\s*\(\s*\$_(GET|POST|REQUEST)/i',
            '/require\s*\(\s*\$_(GET|POST|REQUEST)/i',
            '/require_once\s*\(\s*\$_(GET|POST|REQUEST)/i',
            '/file\s*\(\s*\$_(GET|POST|REQUEST)/i',
        ],
        'severity' => 'CRITICAL',
    ],

    // Database Injection Patterns
    'sql_injection' => [
        'name' => 'Potential SQL Injection',
        'description' => 'Unsafe database query patterns',
        'patterns' => [
            '/\$wpdb->query\s*\([^)]*\$_(GET|POST|REQUEST)/i',
            '/\$wpdb->get_results\s*\([^)]*\$_(GET|POST|REQUEST)/i',
            '/mysql_query\s*\([^)]*\$_(GET|POST|REQUEST)/i',
            '/mysqli_query\s*\([^)]*\$_(GET|POST|REQUEST)/i',
        ],
        'severity' => 'HIGH',
    ],

    // Suspicious File Operations
    'suspicious_files' => [
        'name' => 'Suspicious File Operations',
        'description' => 'File operations that could be malicious',
        'patterns' => [
            '/file_put_contents\s*\([^)]*\$_(GET|POST|REQUEST)/i',
            '/fwrite\s*\([^)]*\$_(GET|POST|REQUEST)/i',
            '/fputs\s*\([^)]*\$_(GET|POST|REQUEST)/i',
            '/chmod\s*\([^)]*0777/i',                       // World-writable permissions
            '/unlink\s*\(\s*\$_(GET|POST|REQUEST)/i',       // Arbitrary file deletion
            '/rmdir\s*\(\s*\$_(GET|POST|REQUEST)/i',        // Arbitrary directory deletion
        ],
        'severity' => 'HIGH',
    ],

    // WordPress Specific Exploits
    'wordpress_exploits' => [
        'name' => 'WordPress-Specific Exploits',
        'description' => 'Patterns targeting WordPress vulnerabilities',
        'patterns' => [
            '/add_action\s*\(\s*["\']wp_ajax_nopriv_/i',    // Unauthenticated AJAX
            '/do_action\s*\(\s*\$_(GET|POST|REQUEST)/i',    // Dynamic actions
            '/apply_filters\s*\(\s*\$_(GET|POST|REQUEST)/i', // Dynamic filters
            '/wp_ajax_nopriv_.*\$_(GET|POST|REQUEST)/i',
        ],
        'severity' => 'MEDIUM',
    ],

    // Obfuscation Patterns
    'obfuscation' => [
        'name' => 'Code Obfuscation',
        'description' => 'Obfuscated code that may hide malicious intent',
        'patterns' => [
            '/\$[a-z]{1,2}\s*=\s*["\'][a-z0-9_]{1,2}["\']/i', // Single char variable names
            '/\$[a-z0-9_]+\s*=\s*\$[a-z0-9_]+\(\$[a-z0-9_]+\)/i', // Variable functions
            '/base64_decode\s*\(\s*["\'][A-Za-z0-9+\/=]{50,}/i', // Long base64 strings
            '/str_rot13\s*\(/i',                             // ROT13 encoding
            '/gzinflate\s*\(/i',                            // Compressed code
            '/gzuncompress\s*\(/i',                         // Compressed code
            '/chr\s*\(\s*\d+\s*\)\s*\./i',                  // Character concatenation
        ],
        'severity' => 'MEDIUM',
    ],
];

// ============================================================================
// GLOBAL COUNTERS
// ============================================================================

$stats = [
    'files_scanned' => 0,
    'files_matched' => 0,
    'directories_scanned' => 0,
    'matches' => [],
    'errors' => [],
    'skipped_files' => [],
    'start_time' => microtime(true),
];

// ============================================================================
// FUNCTIONS
// ============================================================================

/**
 * Output colored text for CLI
 */
function color_text($text, $color = 'white') {
    $colors = [
        'red' => "\033[0;31m",
        'green' => "\033[0;32m",
        'yellow' => "\033[1;33m",
        'blue' => "\033[0;34m",
        'magenta' => "\033[0;35m",
        'cyan' => "\033[0;36m",
        'white' => "\033[0;37m",
        'reset' => "\033[0m",
    ];

    if (php_sapi_name() === 'cli') {
        return $colors[$color] . $text . $colors['reset'];
    }

    // HTML output
    $html_colors = [
        'red' => '#e74c3c',
        'green' => '#2ecc71',
        'yellow' => '#f39c12',
        'blue' => '#3498db',
        'magenta' => '#9b59b6',
        'cyan' => '#1abc9c',
        'white' => '#333',
    ];

    return '<span style="color: ' . $html_colors[$color] . '">' . htmlspecialchars($text) . '</span>';
}

/**
 * Output message
 */
function output($message, $color = 'white') {
    if (php_sapi_name() === 'cli') {
        echo color_text($message, $color) . PHP_EOL;
    } else {
        echo color_text($message, $color) . '<br>' . PHP_EOL;
    }
}

/**
 * Build list of files to scan
 */
function build_file_list($dir, $config, &$stats) {
    $files = [];

    try {
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS),
            RecursiveIteratorIterator::SELF_FIRST
        );

        foreach ($iterator as $file) {
            if ($file->isDir()) {
                $stats['directories_scanned']++;

                // Check if directory should be excluded
                $relative_path = str_replace($config['start_path'], '', $file->getPathname());
                foreach ($config['exclude_dirs'] as $exclude) {
                    if (strpos($relative_path, $exclude) !== false) {
                        continue 2;
                    }
                }
                continue;
            }

            if ($file->isFile()) {
                $extension = strtolower($file->getExtension());
                if (in_array($extension, $config['file_extensions'])) {
                    // Skip files that are too large
                    if ($file->getSize() > $config['max_file_size']) {
                        $stats['skipped_files'][] = [
                            'file' => $file->getPathname(),
                            'reason' => 'File too large (' . format_bytes($file->getSize()) . ')',
                        ];
                        continue;
                    }

                    $files[] = $file->getPathname();
                }
            }
        }
    } catch (Exception $e) {
        $stats['errors'][] = 'Error scanning directory: ' . $e->getMessage();
    }

    return $files;
}

/**
 * Scan a file for malicious patterns
 */
function scan_file($file_path, $patterns, &$stats) {
    $stats['files_scanned']++;

    try {
        $content = file_get_contents($file_path);
        if ($content === false) {
            $stats['errors'][] = 'Could not read file: ' . $file_path;
            return;
        }

        $file_matched = false;

        foreach ($patterns as $category_key => $category) {
            foreach ($category['patterns'] as $pattern) {
                if (preg_match($pattern, $content, $matches)) {
                    if (!$file_matched) {
                        $stats['files_matched']++;
                        $file_matched = true;
                    }

                    // Find line number
                    $lines = explode("\n", $content);
                    $line_number = 0;
                    foreach ($lines as $i => $line) {
                        if (preg_match($pattern, $line)) {
                            $line_number = $i + 1;
                            break;
                        }
                    }

                    $stats['matches'][] = [
                        'file' => $file_path,
                        'category' => $category['name'],
                        'severity' => $category['severity'],
                        'pattern' => $pattern,
                        'match' => trim($matches[0]),
                        'line' => $line_number,
                    ];
                }
            }
        }
    } catch (Exception $e) {
        $stats['errors'][] = 'Error scanning file ' . $file_path . ': ' . $e->getMessage();
    }
}

/**
 * Format bytes to human readable
 */
function format_bytes($bytes) {
    $units = ['B', 'KB', 'MB', 'GB'];
    $bytes = max($bytes, 0);
    $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
    $pow = min($pow, count($units) - 1);
    $bytes /= pow(1024, $pow);
    return round($bytes, 2) . ' ' . $units[$pow];
}

/**
 * Display results
 */
function display_results($stats, $config) {
    output('', 'white');
    output('============================================', 'cyan');
    output('  SECURITY SCAN COMPLETE', 'cyan');
    output('============================================', 'cyan');
    output('', 'white');

    // Summary statistics
    output('SCAN SUMMARY:', 'blue');
    output('  Directories scanned: ' . number_format($stats['directories_scanned']), 'white');
    output('  Files scanned: ' . number_format($stats['files_scanned']), 'white');
    output('  Files with matches: ' . number_format($stats['files_matched']), 'yellow');
    output('  Total matches: ' . number_format(count($stats['matches'])), 'yellow');
    output('  Errors: ' . number_format(count($stats['errors'])), count($stats['errors']) > 0 ? 'red' : 'green');
    output('  Skipped files: ' . number_format(count($stats['skipped_files'])), 'white');

    $elapsed = microtime(true) - $stats['start_time'];
    output('  Scan time: ' . round($elapsed, 2) . ' seconds', 'white');
    output('', 'white');

    // Display matches grouped by severity
    if (count($stats['matches']) > 0) {
        $by_severity = ['CRITICAL' => [], 'HIGH' => [], 'MEDIUM' => [], 'LOW' => []];
        foreach ($stats['matches'] as $match) {
            $by_severity[$match['severity']][] = $match;
        }

        foreach ($by_severity as $severity => $matches) {
            if (count($matches) === 0) continue;

            $color = [
                'CRITICAL' => 'red',
                'HIGH' => 'yellow',
                'MEDIUM' => 'blue',
                'LOW' => 'white',
            ][$severity];

            output('', 'white');
            output('============================================', $color);
            output("  {$severity} SEVERITY MATCHES (" . count($matches) . ")", $color);
            output('============================================', $color);
            output('', 'white');

            foreach ($matches as $match) {
                output('FILE: ' . $match['file'], $color);
                output('  Line: ' . $match['line'], 'white');
                output('  Category: ' . $match['category'], 'white');
                output('  Pattern: ' . $match['pattern'], 'white');
                output('  Match: ' . substr($match['match'], 0, 100), 'magenta');
                output('', 'white');
            }
        }
    } else {
        output('✓ No suspicious patterns detected!', 'green');
        output('', 'white');
    }

    // Display errors
    if (count($stats['errors']) > 0) {
        output('============================================', 'red');
        output('  ERRORS', 'red');
        output('============================================', 'red');
        output('', 'white');

        foreach ($stats['errors'] as $error) {
            output('  ' . $error, 'red');
        }
        output('', 'white');
    }

    // Display skipped files
    if (count($stats['skipped_files']) > 0 && count($stats['skipped_files']) <= 10) {
        output('============================================', 'yellow');
        output('  SKIPPED FILES', 'yellow');
        output('============================================', 'yellow');
        output('', 'white');

        foreach ($stats['skipped_files'] as $skipped) {
            output('  ' . $skipped['file'], 'yellow');
            output('    Reason: ' . $skipped['reason'], 'white');
        }
        output('', 'white');
    }

    // Recommendations
    output('============================================', 'cyan');
    output('  RECOMMENDATIONS', 'cyan');
    output('============================================', 'cyan');
    output('', 'white');

    if (count($stats['matches']) > 0) {
        output('⚠ Suspicious patterns detected!', 'red');
        output('', 'white');
        output('IMMEDIATE ACTIONS:', 'yellow');
        output('  1. Review each match carefully - not all matches are malicious', 'white');
        output('  2. For CRITICAL matches, investigate immediately', 'white');
        output('  3. Check file modification dates (stat command or File Manager)', 'white');
        output('  4. Review Git history for unexpected changes', 'white');
        output('  5. Compare with backup versions if available', 'white');
        output('', 'white');
        output('FALSE POSITIVES:', 'yellow');
        output('  - Security plugins may trigger legitimate alerts', 'white');
        output('  - Debug/development code may match patterns', 'white');
        output('  - Third-party plugins with their own security checks', 'white');
        output('  - Always verify context before removing code', 'white');
    } else {
        output('✓ No suspicious patterns detected', 'green');
        output('', 'white');
        output('SECURITY BEST PRACTICES:', 'yellow');
        output('  1. Run this scanner regularly (weekly/monthly)', 'white');
        output('  2. Keep WordPress and plugins updated', 'white');
        output('  3. Use strong passwords and 2FA', 'white');
        output('  4. Regular backups before updates', 'white');
        output('  5. Monitor webhook logs for unusual activity', 'white');
        output('  6. Review access logs for suspicious requests', 'white');
    }

    output('', 'white');
    output('For more details, see: docs/LOADING-ISSUES.md', 'cyan');
    output('', 'white');
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

// HTML header if running in browser
if (php_sapi_name() !== 'cli') {
    echo '<!DOCTYPE html>
<html>
<head>
    <title>WordPress Security Scanner</title>
    <style>
        body { font-family: Monaco, monospace; background: #1e1e1e; color: #d4d4d4; padding: 20px; }
        pre { white-space: pre-wrap; }
    </style>
</head>
<body><pre>';
}

output('============================================', 'cyan');
output('  WordPress Security & Malware Scanner', 'cyan');
output('  Version 1.0.0 - November 5, 2025', 'cyan');
output('============================================', 'cyan');
output('', 'white');

output('Scan Configuration:', 'blue');
output('  Start Path: ' . $config['start_path'], 'white');
output('  File Extensions: ' . implode(', ', $config['file_extensions']), 'white');
output('  Excluded Directories: ' . implode(', ', $config['exclude_dirs']), 'white');
output('  Max File Size: ' . format_bytes($config['max_file_size']), 'white');
output('', 'white');

output('Building file list...', 'yellow');
$files = build_file_list($config['start_path'], $config, $stats);
output('Found ' . number_format(count($files)) . ' files to scan', 'green');
output('', 'white');

output('Scanning files for malicious patterns...', 'yellow');
$progress_interval = max(1, floor(count($files) / 20)); // Show progress every 5%

foreach ($files as $i => $file) {
    scan_file($file, $patterns, $stats);

    // Show progress
    if ($i % $progress_interval === 0) {
        $percent = round(($i / count($files)) * 100);
        output("Progress: {$percent}% ({$i}/" . count($files) . " files)", 'cyan');
    }
}

output('', 'white');
display_results($stats, $config);

// HTML footer if running in browser
if (php_sapi_name() !== 'cli') {
    echo '</pre></body></html>';
}

// ============================================================================
// SECURITY WARNING
// ============================================================================
output('============================================', 'red');
output('  SECURITY WARNING', 'red');
output('============================================', 'red');
output('', 'white');
output('⚠ DELETE THIS FILE after use or move it outside the web root!', 'red');
output('  This scanner should not remain accessible on a production server.', 'yellow');
output('', 'white');
