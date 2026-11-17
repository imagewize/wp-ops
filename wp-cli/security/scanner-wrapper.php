<?php
/**
 * WordPress Security Scanner - Wrapper Script
 *
 * Runs both targeted and general malware scanners for comprehensive security scanning.
 *
 * @version 1.0.0
 * @date November 5, 2025
 * @see docs/SECURITY-SCANNER-GUIDE.md
 *
 * USAGE:
 *   php wp-cli/security/scanner-wrapper.php [/path/to/scan] [--max-file-size=20MB]
 *   wp eval-file wp-cli/security/scanner-wrapper.php
 *
 * @desc     Run both targeted and general malware scanners in sequence
 * @category security
 * @platform wordpress
 * @runs     local
 * @mutates  false
 * @requires wp
 * @arg      path  optional  {/path/to/scan}  Directory or single file to scan (defaults to WordPress root)
 * @flag     --max-file-size  optional  {20MB}  Size cap for pattern-scanning (bytes, or KB/MB/GB; default 5MB; not applied to a single-file target)
 * @example  wp-ops scanner-wrapper
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

$theme_dir = dirname(__FILE__);
$scan_path = null;
$size_flag = '';

// Get custom path and size cap from command line
if (php_sapi_name() === 'cli' && isset($argv)) {
    for ($i = 1; $i < count($argv); $i++) {
        if (strpos($argv[$i], '--max-file-size=') === 0) {
            $size_flag = $argv[$i];
        } elseif ($scan_path === null && strpos($argv[$i], '--') !== 0) {
            $scan_path = $argv[$i];
        }
    }
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

echo "\033[0;36m";
echo "============================================\n";
echo "  WordPress Security Scanner Suite\n";
echo "  Version 1.0.0 - November 5, 2025\n";
echo "============================================\n";
echo "\033[0m\n";

echo "\033[1;33mThis script runs both security scanners:\033[0m\n";
echo "  1. Targeted Scanner - Site-specific threats\n";
echo "  2. General Scanner  - Broad malware detection\n";
echo "\n";

// Scanner 1: Targeted
echo "\033[0;36m============================================\033[0m\n";
echo "\033[0;36m  RUNNING TARGETED SCANNER (1/2)\033[0m\n";
echo "\033[0;36m============================================\033[0m\n\n";

$cmd1 = "php " . escapeshellarg($theme_dir . "/scanner-targeted.php");
if ($scan_path) {
    $cmd1 .= " " . escapeshellarg($scan_path);
}
if ($size_flag) {
    $cmd1 .= " " . escapeshellarg($size_flag);
}

passthru($cmd1, $return1);

echo "\n\n";

// Scanner 2: General
echo "\033[0;36m============================================\033[0m\n";
echo "\033[0;36m  RUNNING GENERAL SCANNER (2/2)\033[0m\n";
echo "\033[0;36m============================================\033[0m\n\n";

$cmd2 = "php " . escapeshellarg($theme_dir . "/scanner-general.php");
if ($scan_path) {
    $cmd2 .= " " . escapeshellarg($scan_path);
}
if ($size_flag) {
    $cmd2 .= " " . escapeshellarg($size_flag);
}

passthru($cmd2, $return2);

// Final summary
echo "\n\n";
echo "\033[0;36m============================================\033[0m\n";
echo "\033[0;36m  ALL SCANS COMPLETE\033[0m\n";
echo "\033[0;36m============================================\033[0m\n\n";

if ($return1 === 0 && $return2 === 0) {
    echo "\033[0;32m✓ Both scanners completed successfully\033[0m\n";
} else {
    echo "\033[0;31m⚠ One or more scanners reported errors\033[0m\n";
    echo "  Targeted Scanner: " . ($return1 === 0 ? "\033[0;32mOK\033[0m" : "\033[0;31mERROR\033[0m") . "\n";
    echo "  General Scanner:  " . ($return2 === 0 ? "\033[0;32mOK\033[0m" : "\033[0;31mERROR\033[0m") . "\n";
}

echo "\n";
echo "\033[0;33mFor documentation, see: https://wpvilla.in/wordpress-malware-scanners-targeted-general-checksum-verification/\033[0m\n";
echo "\n";
