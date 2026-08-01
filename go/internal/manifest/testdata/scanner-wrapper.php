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
 *
 * @desc     Run both targeted and general malware scanners in sequence
 * @category security
 * @runs     local
 * @requires wp
 * @arg      path  optional  {/path/to/scan}  Directory to scan (defaults to WordPress root)
 * @example  wp-ops wp-cli/security/scanner-wrapper
 * @doc      wp-cli/security/README.md
 */
