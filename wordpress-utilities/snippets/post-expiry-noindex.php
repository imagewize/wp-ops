<?php
/**
 * Auto-noindex posts past their expiry date using WordPress timezone.
 *
 * Hooks into Yoast SEO's wpseo_robots filter to return 'noindex, follow'
 * once the post's expiry date has passed, evaluated in the site's configured
 * timezone (Settings → General → Timezone) rather than UTC.
 *
 * Usage:
 *   1. Copy into your child theme's functions.php (or a custom plugin).
 *   2. Replace the $expiry_categories array with your actual category IDs.
 *      Find them at WP Admin → Posts → Categories (hover = tag_ID=XX in URL).
 *   3. Edit any post — a "Noindex After Date" meta box appears in the sidebar.
 *
 * Dependencies:
 *   - Yoast SEO (free or premium)
 *   - WordPress 5.3+ (wp_timezone() added in 5.3)
 *
 * Meta key: _post_expiry_date (stored as YYYY-MM-DD via HTML date input)
 */

// ---------------------------------------------------------------------------
// 1. Filter robots meta via Yoast
// ---------------------------------------------------------------------------

add_filter( 'wpseo_robots', function( $robots ) {
	if ( ! is_singular( 'post' ) ) {
		return $robots;
	}

	// Limit to specific categories. Replace 0 with real category IDs, e.g. [12, 34].
	$expiry_categories = [ 0 ];

	if ( ! has_term( $expiry_categories, 'category' ) ) {
		return $robots;
	}

	$expiry_date = get_post_meta( get_the_ID(), '_post_expiry_date', true );
	if ( $expiry_date ) {
		$tz  = wp_timezone();                                    // Reads from WP Settings → General
		$now = new DateTime( 'now', $tz );
		$exp = new DateTime( $expiry_date . ' 00:00:00', $tz ); // Expires at midnight local time
		if ( $exp < $now ) {
			return 'noindex, follow';
		}
	}

	return $robots;
} );

// ---------------------------------------------------------------------------
// 2. Meta box — "Noindex After Date" on post edit screen
// ---------------------------------------------------------------------------

add_action( 'add_meta_boxes', function() {
	add_meta_box(
		'post_expiry_date',
		'Noindex After Date',
		function( $post ) {
			$val = get_post_meta( $post->ID, '_post_expiry_date', true );
			echo '<label style="display:block;margin-bottom:4px;">Noindex after:</label>';
			echo '<input type="date" name="post_expiry_date" value="' . esc_attr( $val ) . '" style="width:100%">';
			echo '<p style="margin-top:6px;color:#666;font-size:11px;">Leave blank to never auto-noindex. Once this date passes, Yoast will output noindex for this post automatically.</p>';
		},
		'post',
		'side'
	);
} );

// ---------------------------------------------------------------------------
// 3. Save meta field
// ---------------------------------------------------------------------------

add_action( 'save_post', function( $post_id ) {
	if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) return;
	if ( ! current_user_can( 'edit_post', $post_id ) ) return;
	if ( isset( $_POST['post_expiry_date'] ) ) {
		update_post_meta(
			$post_id,
			'_post_expiry_date',
			sanitize_text_field( $_POST['post_expiry_date'] )
		);
	}
} );
