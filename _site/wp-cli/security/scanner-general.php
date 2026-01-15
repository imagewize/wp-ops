<?php
/**
 * WordPress General Malware Scanner
 *
 * Broad-spectrum malware detection for unknown threats.
 * Companion to security-scanner-targeted.php which focuses on site-specific issues.
 *
 * This scanner detects:
 * - Known malware filenames (c99, r57, shell, etc.)
 * - Pharma hack injections
 * - Generic backdoors and webshells
 * - Suspicious file patterns
 * - SEO spam injections
 *
 * @version 1.0.0
 * @date November 5, 2025
 * @see docs/SECURITY-SCANNER-GUIDE.md
 *
 * SECURITY NOTES:
 * - This script should be deleted after use or secured with authentication
 * - Never leave this file accessible on production without protection
 * - Run via WP-CLI or secure it with IP whitelist
 *
 * USAGE:
 *
 * Via WP-CLI (recommended):
 *   wp eval-file wp-content/themes/robdisbergen/security-scanner-general.php
 *
 * Via Browser (secure with IP check first):
 *   https://yoursite.com/wp-content/themes/robdisbergen/security-scanner-general.php
 *
 * Via Command Line:
 *   php wp-content/themes/robdisbergen/security-scanner-general.php [/path/to/scan]
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
// Usage: php security-scanner-general.php /path/to/scan
//        wp eval-file security-scanner-general.php --path=/path/to/scan
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
    'file_extensions' => ['php', 'js', 'txt', 'htm', 'html', 'htaccess'],
    'max_execution_time' => 300,
    'max_file_size' => 5 * 1024 * 1024, // 5MB
];

// Set execution limits
ini_set('max_execution_time', $config['max_execution_time']);
set_time_limit($config['max_execution_time']);
ini_set('display_errors', '1');

// ============================================================================
// MALWARE PATTERNS - General Detection
// ============================================================================

/**
 * Known malware filenames and patterns
 */
$malware_filenames = [
    // Known webshells
    'c99.php', 'r57.php', 'shell.php', 'backdoor.php', 'wso.php',
    'c100.php', 'b374k.php', 'adminer.php', 'pma.php', 'mysql.php',
    'webshl.php', 'webshell.php', 'sh3ll.php', 'symlink.php',

    // Common malware patterns (exact matches only)
    '/^x\.php$/', '/^xx\.php$/', '/^xxx\.php$/', '/^mmd\.php$/', '/^mad\.php$/',
    '/^killer\.php$/', '/^changeall\.php$/', '/^alfa\.php$/', '/alfacgiapi/',
    '/^uploader\.php$/', '/uploadx/', '/^mass\.php$/', '/^bypass\.php$/',

    // Base64 in filename
    'base64', 'b64',

    // Suspicious extensions
    '.php.suspected', '.php.bak', '.bak.php',

    // Hidden files
    '.htaccess.bak', '.user.ini',

    // Crypto miners
    'coinhive', 'cryptonight', 'miner.js',
];

/**
 * Pattern categories for malware detection
 */
$patterns = [
    // Pharma Hack Patterns
    'pharma_hack' => [
        'name' => 'Pharmaceutical Spam Injection',
        'description' => 'Common pharma hack keywords and patterns',
        'patterns' => [
            '/viagra/i',
            '/cialis/i',
            '/levitra/i',
            '/pharmacy/i',
            '/phentermine/i',
            '/xenical/i',
            '/adipex/i',
            '/ambien/i',
            '/tramadol/i',
            '/ultram/i',
            '/carisoprodol/i',
            '/soma[\s\-]online/i',
            '/cheap[\s\-]?medications?/i',
            '/online[\s\-]?pharmacy/i',
            '/drug[\s\-]?store/i',
            '/prescription[\s\-]?drugs/i',
            '/<a[^>]*href=[^>]*viagra/i',
            '/<a[^>]*href=[^>]*cialis/i',
            '/<a[^>]*href=[^>]*pharmacy/i',
        ],
        'severity' => 'CRITICAL',
    ],

    // SEO Spam Injection
    'seo_spam' => [
        'name' => 'SEO Spam Injection',
        'description' => 'Hidden links and SEO spam',
        'patterns' => [
            '/display\s*:\s*none[^>]*>.*<a\s+href/is',
            '/visibility\s*:\s*hidden[^>]*>.*<a\s+href/is',
            '/position\s*:\s*absolute[^>]*left\s*:\s*-\d+/is',
            '/<div[^>]*style=["\'][^"\']*display:\s*none[^"\']*["\'][^>]*>.*?<a/is',
            '/<iframe[^>]*width=["\']0["\'][^>]*>/i',
            '/<iframe[^>]*height=["\']0["\'][^>]*>/i',
            '/eval\s*\(\s*unescape/i',
        ],
        'severity' => 'CRITICAL',
    ],

    // Known Webshells
    'webshell_signatures' => [
        'name' => 'Known Webshell Signatures',
        'description' => 'Signatures from known webshells',
        'patterns' => [
            '/c99shell/i',
            '/r57shell/i',
            '/wso\s*shell/i',
            '/FilesMan/i',
            '/Phpinfo\(\)/i',
            '/Safe0ver/i',
            '/uname -a/i',
            '/php_uname/i',
            '/safe_mode/i',
            '/disable_functions/i',
            '/eval\(gzinflate\(base64_decode/i',
            '/eval\(base64_decode\(gzinflate/i',
            '/str_rot13.*base64_decode/i',
            '/gzuncompress.*base64_decode/i',
            '/base64_decode.*gzinflate/i',
        ],
        'severity' => 'CRITICAL',
    ],

    // Multiple Encoding Layers
    'multiple_encoding' => [
        'name' => 'Multiple Encoding Layers',
        'description' => 'Multiple layers of encoding (common in malware)',
        'patterns' => [
            '/base64_decode\s*\(\s*base64_decode/i',
            '/base64_decode\s*\(\s*gzinflate\s*\(\s*base64_decode/i',
            '/gzinflate\s*\(\s*base64_decode\s*\(\s*str_rot13/i',
            '/str_rot13\s*\(\s*base64_decode\s*\(\s*gzinflate/i',
            '/eval\s*\(\s*str_rot13\s*\(\s*base64_decode/i',
        ],
        'severity' => 'CRITICAL',
    ],

    // Backdoor Functions
    'backdoor_functions' => [
        'name' => 'Backdoor Function Calls',
        'description' => 'Functions commonly used in backdoors',
        'patterns' => [
            '/assert\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/eval\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/system\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/exec\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/shell_exec\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/passthru\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/proc_open\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/popen\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/pcntl_exec\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)/i',
        ],
        'severity' => 'CRITICAL',
    ],

    // Encoded Eval Patterns
    'encoded_eval' => [
        'name' => 'Encoded Eval Patterns',
        'description' => 'Eval with various encoding schemes',
        'patterns' => [
            '/\$[a-z0-9_]+\s*=\s*base64_decode[^;]+;\s*eval\s*\(/i',
            '/\$[a-z0-9_]+\s*=\s*gzinflate[^;]+;\s*eval\s*\(/i',
            '/\$[a-z0-9_]+\s*=\s*str_rot13[^;]+;\s*eval\s*\(/i',
            '/\$[a-z0-9_]+\s*=\s*gzuncompress[^;]+;\s*eval\s*\(/i',
            '/eval\s*\(\s*\$\$[a-z0-9_]+\)/i', // Variable variables
        ],
        'severity' => 'CRITICAL',
    ],

    // File Upload Backdoors
    'file_upload_backdoor' => [
        'name' => 'File Upload Backdoors',
        'description' => 'Patterns for file upload exploits',
        'patterns' => [
            '/move_uploaded_file\s*\([^,]+,\s*\$_(GET|POST|REQUEST)/i',
            '/copy\s*\(\s*\$_FILES.*tmp_name/i',
            '/file_put_contents\s*\([^,]+,\s*\$_(GET|POST|REQUEST|FILES)/i',
            '/fwrite\s*\([^,]+,\s*\$_(GET|POST|REQUEST|FILES)/i',
        ],
        'severity' => 'HIGH',
    ],

    // Database Backdoors
    'database_backdoor' => [
        'name' => 'Database Backdoor Patterns',
        'description' => 'SQL injection and database manipulation',
        'patterns' => [
            '/SELECT.*INTO\s+OUTFILE/i',
            '/LOAD_FILE\s*\(/i',
            '/UNION.*SELECT.*FROM/i',
            '/mysql_query\s*\([^)]*\$_(GET|POST|REQUEST|COOKIE)/i',
            '/mysqli_query\s*\([^)]*\$_(GET|POST|REQUEST|COOKIE)/i',
        ],
        'severity' => 'HIGH',
    ],

    // Hidden Iframes
    'hidden_iframe' => [
        'name' => 'Hidden Iframes',
        'description' => 'Hidden iframes often used for malware distribution',
        'patterns' => [
            '/<iframe[^>]*style=["\'][^"\']*display\s*:\s*none/i',
            '/<iframe[^>]*style=["\'][^"\']*visibility\s*:\s*hidden/i',
            '/<iframe[^>]*width=["\']0["\'][^>]*height=["\']0["\']/i',
            '/<iframe[^>]*height=["\']1["\'][^>]*width=["\']1["\']/i',
        ],
        'severity' => 'HIGH',
    ],

    // Suspicious Variable Names
    'suspicious_variables' => [
        'name' => 'Suspicious Variable Names',
        'description' => 'Variable names commonly used in malware',
        'patterns' => [
            '/\$GLOBALS\s*\[\s*["\'][a-z0-9]{32}["\']\s*\]/i', // MD5 hash keys
            '/\$[a-z]{50,}/i', // Very long variable names
            '/\$_+[A-Z]+_+\[/i', // Mimicking superglobals like $__GET__
        ],
        'severity' => 'MEDIUM',
    ],

    // Remote File Inclusion
    'remote_inclusion' => [
        'name' => 'Remote File Inclusion',
        'description' => 'Remote file inclusion attempts',
        'patterns' => [
            '/include\s*\(["\']https?:/i',
            '/include_once\s*\(["\']https?:/i',
            '/require\s*\(["\']https?:/i',
            '/require_once\s*\(["\']https?:/i',
            '/file_get_contents\s*\(["\']https?:.*\.php/i',
            '/fopen\s*\(["\']https?:.*\.php/i',
        ],
        'severity' => 'HIGH',
    ],

    // Suspicious Functions
    'suspicious_functions' => [
        'name' => 'Suspicious Function Usage',
        'description' => 'Functions rarely used in legitimate code',
        'patterns' => [
            '/ini_set\s*\(\s*["\']safe_mode["\']/i',
            '/ini_set\s*\(\s*["\']disable_functions["\']/i',
            '/ini_restore\s*\(/i',
            '/dl\s*\(\s*["\'][^"\']+\.so["\']/i', // Loading shared libraries
            '/apache_child_terminate\s*\(/i',
            '/posix_kill\s*\(/i',
            '/posix_setsid\s*\(/i',
        ],
        'severity' => 'HIGH',
    ],

    // Code Injection
    'code_injection' => [
        'name' => 'Code Injection Patterns',
        'description' => 'Various code injection techniques',
        'patterns' => [
            '/preg_replace\s*\(["\'].*["\']\s*,\s*\$_(GET|POST|REQUEST)/i',
            '/preg_filter\s*\(["\'].*["\']\s*,\s*\$_(GET|POST|REQUEST)/i',
            '/mb_ereg_replace\s*\([^,]+,[^,]+,[^,]+,\s*["\']e["\']/i',
        ],
        'severity' => 'HIGH',
    ],

    // Long Base64 Strings
    'long_base64' => [
        'name' => 'Suspiciously Long Base64 Strings',
        'description' => 'Very long base64 encoded strings (often malicious payload)',
        'patterns' => [
            '/["\'][A-Za-z0-9+\/=]{500,}["\']/i', // 500+ character base64
        ],
        'severity' => 'MEDIUM',
    ],

    // Hexadecimal Strings
    'hex_strings' => [
        'name' => 'Long Hexadecimal Strings',
        'description' => 'Long hex strings that may contain encoded malware',
        'patterns' => [
            '/["\']\\\\x[0-9a-f]{2}(\\\\x[0-9a-f]{2}){50,}["\']/i',
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
    'suspicious_filenames' => [],
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
 * Check if filename matches known malware patterns
 */
function check_malware_filename($filename, $malware_filenames) {
    $basename = strtolower(basename($filename));

    foreach ($malware_filenames as $malware_name) {
        // Handle regex patterns (start with /)
        if (substr($malware_name, 0, 1) === '/') {
            if (preg_match($malware_name, $basename)) {
                return $malware_name;
            }
        }
        // Handle string patterns (case-insensitive substring match)
        else {
            if (stripos($basename, $malware_name) !== false) {
                return $malware_name;
            }
        }
    }

    return false;
}

/**
 * Build list of files to scan
 */
function build_file_list($dir, $config, $malware_filenames, &$stats) {
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

                // Check filename for malware patterns
                $malware_match = check_malware_filename($file->getPathname(), $malware_filenames);
                if ($malware_match) {
                    $stats['suspicious_filenames'][] = [
                        'file' => $file->getPathname(),
                        'pattern' => $malware_match,
                        'size' => $file->getSize(),
                        'modified' => date('Y-m-d H:i:s', $file->getMTime()),
                    ];
                }

                if (in_array($extension, $config['file_extensions']) || $extension === '') {
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
    output('  GENERAL MALWARE SCAN COMPLETE', 'cyan');
    output('============================================', 'cyan');
    output('', 'white');

    // Summary statistics
    output('SCAN SUMMARY:', 'blue');
    output('  Directories scanned: ' . number_format($stats['directories_scanned']), 'white');
    output('  Files scanned: ' . number_format($stats['files_scanned']), 'white');
    output('  Suspicious filenames: ' . number_format(count($stats['suspicious_filenames'])), count($stats['suspicious_filenames']) > 0 ? 'red' : 'green');
    output('  Files with matches: ' . number_format($stats['files_matched']), 'yellow');
    output('  Total matches: ' . number_format(count($stats['matches'])), 'yellow');
    output('  Errors: ' . number_format(count($stats['errors'])), count($stats['errors']) > 0 ? 'red' : 'green');
    output('  Skipped files: ' . number_format(count($stats['skipped_files'])), 'white');

    $elapsed = microtime(true) - $stats['start_time'];
    output('  Scan time: ' . round($elapsed, 2) . ' seconds', 'white');
    output('', 'white');

    // Display suspicious filenames FIRST (highest priority)
    if (count($stats['suspicious_filenames']) > 0) {
        output('============================================', 'red');
        output('  ⚠️  SUSPICIOUS FILENAMES DETECTED (' . count($stats['suspicious_filenames']) . ')', 'red');
        output('============================================', 'red');
        output('', 'white');
        output('The following files have names matching known malware:', 'yellow');
        output('These should be investigated IMMEDIATELY!', 'red');
        output('', 'white');

        foreach ($stats['suspicious_filenames'] as $file) {
            output('FILE: ' . $file['file'], 'red');
            output('  Matched pattern: ' . $file['pattern'], 'yellow');
            output('  File size: ' . format_bytes($file['size']), 'white');
            output('  Last modified: ' . $file['modified'], 'white');
            output('  ⚠️  ACTION: Review this file immediately and delete if malicious', 'red');
            output('', 'white');
        }
    }

    // Display pattern matches grouped by severity
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
        if (count($stats['suspicious_filenames']) === 0) {
            output('✓ No suspicious patterns or filenames detected!', 'green');
            output('', 'white');
        }
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

    // Display skipped files (limit to 10)
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

    $total_threats = count($stats['suspicious_filenames']) + count($stats['matches']);

    if ($total_threats > 0) {
        output('⚠️  THREATS DETECTED!', 'red');
        output('', 'white');
        output('IMMEDIATE ACTIONS:', 'yellow');

        if (count($stats['suspicious_filenames']) > 0) {
            output('  1. PRIORITY: Review suspicious filenames FIRST', 'red');
            output('     - These files match known malware naming patterns', 'white');
            output('     - Check when they were created/modified', 'white');
            output('     - Review their content', 'white');
            output('     - Delete if malicious', 'white');
        }

        output('  2. Review pattern matches by severity (CRITICAL first)', 'white');
        output('  3. Check file modification dates: stat filename', 'white');
        output('  4. Review Git history for unexpected changes', 'white');
        output('  5. Compare with backup versions', 'white');
        output('  6. Isolate infected files before deletion', 'white');
        output('  7. Change all passwords if compromise confirmed', 'white');
        output('', 'white');
        output('FALSE POSITIVES:', 'yellow');
        output('  - Pharma keywords may appear in legitimate medical sites', 'white');
        output('  - Long base64 strings may be legitimate data', 'white');
        output('  - Always verify context before removing code', 'white');
        output('  - Check against clean backup before deleting', 'white');
    } else {
        output('✓ No malware detected', 'green');
        output('', 'white');
        output('SECURITY BEST PRACTICES:', 'yellow');
        output('  1. Run this scanner monthly for unknown threats', 'white');
        output('  2. Run security-scanner-targeted.php weekly', 'white');
        output('  3. Keep WordPress and plugins updated', 'white');
        output('  4. Monitor file system for new suspicious files', 'white');
        output('  5. Review server access logs regularly', 'white');
        output('  6. Implement file integrity monitoring', 'white');
    }

    output('', 'white');
    output('For targeted scanning, use: security-scanner-targeted.php', 'cyan');
    output('For documentation, see: docs/SECURITY-SCANNER-GUIDE.md', 'cyan');
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
    <title>WordPress General Malware Scanner</title>
    <style>
        body { font-family: Monaco, monospace; background: #1e1e1e; color: #d4d4d4; padding: 20px; }
        pre { white-space: pre-wrap; }
    </style>
</head>
<body><pre>';
}

output('============================================', 'cyan');
output('  WordPress General Malware Scanner', 'cyan');
output('  Version 1.0.0 - November 5, 2025', 'cyan');
output('  Broad-spectrum malware detection', 'cyan');
output('============================================', 'cyan');
output('', 'white');

output('Scan Configuration:', 'blue');
output('  Start Path: ' . $config['start_path'], 'white');
output('  File Extensions: ' . implode(', ', $config['file_extensions']), 'white');
output('  Excluded Directories: ' . implode(', ', $config['exclude_dirs']), 'white');
output('  Max File Size: ' . format_bytes($config['max_file_size']), 'white');
output('', 'white');

output('Building file list and checking filenames...', 'yellow');
$files = build_file_list($config['start_path'], $config, $malware_filenames, $stats);
output('Found ' . number_format(count($files)) . ' files to scan', 'green');

if (count($stats['suspicious_filenames']) > 0) {
    output('⚠️  Found ' . count($stats['suspicious_filenames']) . ' suspicious filenames!', 'red');
}
output('', 'white');

output('Scanning files for malware patterns...', 'yellow');
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
output('⚠️  DELETE THIS FILE after use or move it outside the web root!', 'red');
output('  This scanner should not remain accessible on a production server.', 'yellow');
output('', 'white');
