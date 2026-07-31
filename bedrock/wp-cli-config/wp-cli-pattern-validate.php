<?php
/**
 * WP-CLI command for validating and fixing pattern files using WordPress core parser.
 *
 * Uses parse_blocks() + serialize_blocks() to round-trip pattern content through
 * WordPress's own serializer. The output IS the canonical form WordPress would store
 * after a save — so --fix writes back exactly what WP expects, with no browser needed.
 *
 * PHP tags inside block HTML are treated as literal text by parse_blocks() and
 * round-trip cleanly — no stripping required.
 *
 * Place this file in your Bedrock site root alongside wp-cli.yml so it is
 * auto-required on every `wp` invocation (see wp-cli.yml's `require` key).
 *
 * ## EXAMPLES
 *
 *     # Validate all patterns (dry run, shows what would change)
 *     wp pattern validate web/app/themes/your-theme/patterns/
 *
 *     # Show unified diff without fixing
 *     wp pattern validate web/app/themes/your-theme/patterns/ --diff
 *
 *     # Auto-fix all structural issues in-place
 *     wp pattern validate web/app/themes/your-theme/patterns/ --fix
 *
 *     # Fix and write logs to docs/pattern-logs/
 *     wp pattern validate web/app/themes/your-theme/patterns/ --fix --log
 *
 *     # Fix a single file
 *     wp pattern validate web/app/themes/your-theme/patterns/hero.php --fix
 *
 *     # Fix a subdirectory only
 *     wp pattern validate web/app/themes/your-theme/patterns/woocommerce/ --fix
 *
 *     # If not auto-required via wp-cli.yml, pass --require explicitly:
 *     wp --require=wp-cli-pattern-validate.php pattern validate web/app/themes/your-theme/patterns/
 *
 * @desc     Validate/fix block pattern files by round-tripping through parse_blocks()/serialize_blocks()
 * @category wp-cli-config
 * @runs     local
 * @requires wp
 * @arg      path               required  {web/app/themes/theme-name/patterns/}  Pattern file or directory (recursive)
 * @flag     --fix              optional  {}  Rewrite files in-place with the canonical output
 * @flag     --diff             optional  {}  Print a unified diff for files that need changes
 * @flag     --log              optional  {}  Write per-pattern diffs and a summary to docs/pattern-logs/<date>/
 * @flag     --log-dir          optional  {docs/pattern-logs}  Override the log directory
 * @flag     --compliance       optional  {}  Also run project-specific compliance checks
 * @flag     --compliance-only  optional  {}  Skip Gutenberg validation, only run compliance checks
 * @example  wp-ops bedrock/wp-cli-config/wp-cli-pattern-validate web/app/themes/theme-name/patterns/ --fix
 * @doc      bedrock/wp-cli-config/README.md
 */

if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) {
	exit;
}

/**
 * Validates and fixes WordPress block pattern files using the WordPress block parser.
 */
class Pattern_Validate_Command extends WP_CLI_Command {

	/**
	 * Validates (and optionally fixes) pattern files using WordPress block parser.
	 *
	 * ## OPTIONS
	 *
	 * <path>...
	 * : Pattern file or directory. Directories are scanned recursively.
	 *
	 * [--fix]
	 * : Rewrite each file with the canonical serialized output in-place.
	 *
	 * [--diff]
	 * : Print a unified diff for each file that needs changes (dry-run).
	 *
	 * [--log]
	 * : Write per-pattern diff files and a summary to docs/pattern-logs/<date>/.
	 *
	 * [--log-dir=<path>]
	 * : Override the log directory (default: <site-root>/docs/pattern-logs/).
	 *
	 * [--compliance]
	 * : Also run project-specific compliance checks after structural validation.
	 *
	 * [--compliance-only]
	 * : Skip Gutenberg validation and only run compliance checks.
	 *
	 * @subcommand validate
	 */
	public function validate( $args, $assoc_args ) {
		$fix             = \WP_CLI\Utils\get_flag_value( $assoc_args, 'fix', false );
		$diff            = \WP_CLI\Utils\get_flag_value( $assoc_args, 'diff', false );
		$log             = \WP_CLI\Utils\get_flag_value( $assoc_args, 'log', false );
		$compliance      = \WP_CLI\Utils\get_flag_value( $assoc_args, 'compliance', false );
		$compliance_only = \WP_CLI\Utils\get_flag_value( $assoc_args, 'compliance-only', false );

		$repo_root       = dirname( __FILE__ );
		$default_log_dir = $repo_root . '/docs/pattern-logs';
		$log_dir         = \WP_CLI\Utils\get_flag_value( $assoc_args, 'log-dir', $default_log_dir );

		$files = $this->get_pattern_files( $args );

		if ( empty( $files ) ) {
			WP_CLI::error( 'No pattern files found. Specify a .php pattern file or directory.' );
		}

		WP_CLI::line( '' );
		WP_CLI::line( WP_CLI::colorize( '%BPattern Validation — ' . count( $files ) . ' file(s)%n' ) );
		WP_CLI::line( str_repeat( '-', 55 ) );

		if ( $compliance_only ) {
			$this->run_compliance_checks( $files, $fix );
			exit( 0 );
		}

		$result = $this->validate_with_gutenberg( $files, $fix, $diff, $log ? $log_dir : null );

		if ( $compliance && ! $result['error'] ) {
			$this->run_compliance_checks( $files, $fix );
		}

		exit( $result['has_issues'] ? 1 : 0 );
	}

	/**
	 * Collect all .php pattern files from the given paths, recursively.
	 *
	 * @param array $args Paths from CLI arguments.
	 * @return array Unique list of absolute file paths.
	 */
	private function get_pattern_files( $args ) {
		$files = array();

		foreach ( $args as $path ) {
			$path = rtrim( $path, '/' );

			if ( is_dir( $path ) ) {
				$iter = new RecursiveIteratorIterator(
					new RecursiveDirectoryIterator( $path, RecursiveDirectoryIterator::SKIP_DOTS )
				);
				foreach ( $iter as $file ) {
					if ( $file->getExtension() === 'php' && $this->is_valid_pattern_file( $file->getPathname() ) ) {
						$files[] = $file->getPathname();
					}
				}
			} elseif ( is_file( $path ) && pathinfo( $path, PATHINFO_EXTENSION ) === 'php' ) {
				if ( $this->is_valid_pattern_file( $path ) ) {
					$files[] = $path;
				}
			}
		}

		sort( $files );
		return array_unique( $files );
	}

	/**
	 * Skip WooCommerce plugin-bundled patterns — those follow WC standards, not theme rules.
	 *
	 * @param string $file Absolute path.
	 * @return bool True if the file should be validated.
	 */
	private function is_valid_pattern_file( $file ) {
		$skip = array(
			'/wp-content/plugins/woocommerce/patterns/',
			'/woocommerce/patterns/',
		);
		foreach ( $skip as $needle ) {
			if ( false !== strpos( $file, $needle ) ) {
				return false;
			}
		}
		return true;
	}

	/**
	 * Core validation loop: parse → serialize → compare → optionally fix and log.
	 *
	 * @param array       $files   Pattern files to process.
	 * @param bool        $fix     Rewrite files in-place.
	 * @param bool        $diff    Print unified diff to stdout.
	 * @param string|null $log_dir Write log files here, or null to skip.
	 * @return array { has_issues: bool, error: bool, fixed: int, needs_review: int }
	 */
	private function validate_with_gutenberg( $files, $fix, $diff, $log_dir ) {
		$has_issues   = false;
		$fixed_count  = 0;
		$review_count = 0;
		$pass_count   = 0;
		$error        = false;
		$date_slug    = gmdate( 'Y-m-d' );
		$log_entries  = array();

		if ( $log_dir ) {
			$run_log_dir = $log_dir . '/' . $date_slug;
			if ( ! is_dir( $run_log_dir ) ) {
				wp_mkdir_p( $run_log_dir );
			}
		}

		foreach ( $files as $file ) {
			$basename = basename( $file );
			$raw      = file_get_contents( $file );

			// Extract block content.
			// Format 1: return 'string'; (some WP core patterns)
			// Format 2: PHP docblock header ending with closing tag, raw block HTML follows
			if ( preg_match( '/return\s+[\'"](.+?)[\'"]\s*;/s', $raw, $m ) ) {
				$block_content = $m[1];
				$header        = '';
				$format        = 'return';
			} elseif ( preg_match( '/^([\s\S]*?\?>)([\s\S]*)$/s', $raw, $m ) ) {
				$header        = $m[1];
				$block_content = ltrim( $m[2] );
				$format        = 'standard';
			} else {
				WP_CLI::warning( "Cannot extract block content from: {$basename}" );
				$log_entries[ $basename ] = 'SKIP — no extractable block content';
				continue;
			}

			// Round-trip through WordPress's own serializer.
			$parsed    = parse_blocks( $block_content );
			$canonical = serialize_blocks( $parsed );

			// serialize_block_attributes() unicode-escapes <, >, &, and -- to keep block
			// comment delimiters safe in HTML. Reverse these for PHP source files so that
			// PHP open/close tags, CSS variables (--wp--...), and & in metadata stay literal.
			$canonical = str_replace(
				array( '<', '>', '&', '--' ),
				array( '<', '>', '&', '--' ),
				$canonical
			);

			$canonical = rtrim( $canonical );
			$original  = rtrim( $block_content );

			if ( $original === $canonical ) {
				WP_CLI::line( WP_CLI::colorize( '%GPASS%n  ' ) . $basename );
				$pass_count++;
				$log_entries[ $basename ] = 'PASS';
				continue;
			}

			$has_issues = true;
			$diff_text  = $this->generate_diff( $original, $canonical );

			if ( $fix ) {
				if ( 'return' === $format ) {
					$new_raw = str_replace( $block_content, $canonical, $raw );
				} else {
					$new_raw = $header . "\n" . $canonical . "\n";
				}

				$written = file_put_contents( $file, $new_raw );
				if ( false !== $written ) {
					$fixed_count++;
					WP_CLI::line( WP_CLI::colorize( '%YFIXED%n ' ) . $basename );
					$log_entries[ $basename ] = 'FIXED';
				} else {
					$error = true;
					WP_CLI::warning( "Could not write: {$basename}" );
					$log_entries[ $basename ] = 'ERROR — write failed';
				}
			} else {
				$review_count++;
				WP_CLI::line( WP_CLI::colorize( '%RFAIL%n  ' ) . $basename );
				$log_entries[ $basename ] = 'NEEDS_FIX';
			}

			if ( $diff && ! $fix ) {
				WP_CLI::line( $diff_text );
			}

			if ( $log_dir && ! empty( $diff_text ) ) {
				file_put_contents( $run_log_dir . '/' . $basename . '.diff', $diff_text );
			}
		}

		WP_CLI::line( '' );
		WP_CLI::line( str_repeat( '-', 55 ) );
		WP_CLI::line( WP_CLI::colorize( '%BSummary%n' ) );
		WP_CLI::line( str_repeat( '-', 55 ) );
		WP_CLI::line( WP_CLI::colorize( '%GPass:%n        ' ) . $pass_count );
		if ( $fix ) {
			WP_CLI::line( WP_CLI::colorize( '%YFixed:%n       ' ) . $fixed_count );
		} else {
			WP_CLI::line( WP_CLI::colorize( '%RNeeds fix:%n   ' ) . $review_count );
		}

		if ( $log_dir ) {
			$this->write_summary( $run_log_dir, $date_slug, $log_entries, $pass_count, $fixed_count, $review_count );
			WP_CLI::line( '' );
			WP_CLI::line( "Logs written to: {$run_log_dir}/" );
		}

		return array(
			'has_issues'   => $has_issues,
			'error'        => $error,
			'fixed'        => $fixed_count,
			'needs_review' => $review_count,
		);
	}

	/**
	 * Generate a unified diff between two strings, returned as a string.
	 *
	 * @param string $old Original content.
	 * @param string $new Canonical content.
	 * @return string Unified diff output.
	 */
	private function generate_diff( $old, $new ) {
		$old_file = tempnam( sys_get_temp_dir(), 'wp_pat_old_' );
		$new_file = tempnam( sys_get_temp_dir(), 'wp_pat_new_' );

		file_put_contents( $old_file, $old );
		file_put_contents( $new_file, $new );

		$output = array();
		exec( 'diff -u ' . escapeshellarg( $old_file ) . ' ' . escapeshellarg( $new_file ), $output );

		unlink( $old_file );
		unlink( $new_file );

		return implode( "\n", array_slice( $output, 2 ) );
	}

	/**
	 * Write a markdown summary file to the log directory.
	 *
	 * @param string $dir       Log run directory.
	 * @param string $date_slug Date string for the heading.
	 * @param array  $entries   basename => status string.
	 * @param int    $pass      Pass count.
	 * @param int    $fixed     Fixed count.
	 * @param int    $review    Needs-review count.
	 */
	private function write_summary( $dir, $date_slug, $entries, $pass, $fixed, $review ) {
		$lines = array(
			"# Pattern Validation — {$date_slug}",
			'',
			'| Status | Count |',
			'|--------|------:|',
			"| Pass   | {$pass} |",
			"| Fixed  | {$fixed} |",
			"| Review | {$review} |",
			'',
			'## Per-Pattern Results',
			'',
		);

		foreach ( $entries as $file => $status ) {
			$lines[] = "- `{$file}` — {$status}";
		}

		file_put_contents( $dir . '/summary.md', implode( "\n", $lines ) . "\n" );
	}

	/**
	 * Hook for project-specific compliance checks (pass-2 static analysis).
	 *
	 * The default implementation is a stub — adapt this method for your project's
	 * own compliance checker (e.g. a custom PHP script that enforces theme-specific
	 * block rules). The --compliance and --compliance-only flags trigger this method.
	 *
	 * @param array $files Pattern files.
	 * @param bool  $fix   Apply compliance auto-fixes.
	 */
	private function run_compliance_checks( $files, $fix ) {
		WP_CLI::line( '' );
		WP_CLI::line( WP_CLI::colorize( '%BCompliance checks%n' ) );
		WP_CLI::line( str_repeat( '-', 55 ) );

		// Point $checker at your project's compliance script.
		// Example: dirname( __FILE__ ) . '/scripts/pattern-check/class-compliancechecker.php'
		$checker = null;

		if ( ! $checker || ! file_exists( $checker ) ) {
			WP_CLI::warning( 'No compliance checker configured — adapt run_compliance_checks() for your project.' );
			return;
		}

		$cmd    = 'php ' . escapeshellarg( $checker ) . ' ' . implode( ' ', array_map( 'escapeshellarg', $files ) );
		$cmd   .= $fix ? ' --autofix' : '';
		$output = array();
		$code   = 0;
		exec( $cmd, $output, $code );

		foreach ( $output as $line ) {
			WP_CLI::line( $line );
		}

		if ( $code !== 0 ) {
			WP_CLI::warning( "Compliance check exited with code {$code}." );
		}
	}
}

$_cmd = new Pattern_Validate_Command();
WP_CLI::add_command( 'pattern validate', array( $_cmd, 'validate' ) );
