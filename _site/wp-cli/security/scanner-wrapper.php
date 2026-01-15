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
 *   php wp-cli/security/scanner-wrapper.php [/path/to/scan]
 *   wp eval-file wp-cli/security/scanner-wrapper.php
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

$theme_dir = dirname(__FILE__);
$scan_path = null;

// Get custom path from command line
if (php_sapi_name() === 'cli' && isset($argv[1])) {
    $scan_path = $argv[1];
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
echo "\033[0;33mFor documentation, see: wp-cli/security/SECURITY-GUIDE.md\033[0m\n";
echo "\n";
