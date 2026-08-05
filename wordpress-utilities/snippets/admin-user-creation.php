<?php
/**
 * Temporary admin user creation for WordPress.
 *
 * Adds a one-time administrator user via functions.php. The function
 * checks if the user already exists before creating it, and should be
 * REMOVED immediately after the user is created for security.
 *
 * SECURITY WARNING:
 * - This snippet contains credentials. NEVER commit this to version control.
 * - Remove this entire code block from functions.php after first login.
 * - Use WP-CLI (admin-user-creation-wpcli.md) for a safer, non-code approach.
 *
 * Usage:
 *   1. Copy this entire block into your theme's functions.php (or mu-plugin).
 *   2. Replace the placeholder values:
 *      - USERNAME: Temporary admin username (e.g., 'temp_admin')
 *      - EMAIL: Temporary email (e.g., 'temp@example.com')
 *      - PASSWORD: Strong password (or use wp_generate_password)
 *   3. Save and load any page on your site once to trigger creation.
 *   4. Log in with the new credentials.
 *   5. IMMEDIATELY remove this code from functions.php.
 *
 * Better alternative:
 *   Use WP-CLI: wp user create USERNAME EMAIL --role=administrator --user_pass=PASSWORD
 *
 * @desc     Temporary admin user creation snippet for functions.php (remove after use)
 * @category snippets
 * @platform wordpress
 * @doc      wordpress-utilities/snippets/admin-user-creation-wpcli.md
 */

// =============================================================================
// TEMPORARY ADMIN USER CREATION - REMOVE AFTER USE
// =============================================================================

add_action('wp_loaded', 'wpops_create_temporary_admin_user');
/**
 * Create a temporary administrator user if they don't already exist.
 *
 * Hooked to 'wp_loaded' (earlier than 'init') to ensure user is created
 * before any admin-area checks that might require authentication.
 */
function wpops_create_temporary_admin_user() {
    // =========================================================================
    // CONFIGURATION - REPLACE THESE VALUES
    // =========================================================================
    
    $username = 'REPLACE_ME_USERNAME';    // e.g., 'temp_admin'
    $email    = 'REPLACE_ME@examp.le';   // e.g., 'temp@example.com' (use real domain)
    $password = 'REPLACE_ME_PASSWORD';    // e.g., wp_generate_password(16)
    $role     = 'administrator';         // Keep as administrator
    
    // =========================================================================
    // DO NOT EDIT BELOW THIS LINE
    // =========================================================================
    
    // Check if user already exists
    if (get_user_by('login', $username) || get_user_by('email', $email)) {
        return;
    }
    
    // Sanity check: don't create if username is still placeholder
    if (strpos($username, 'REPLACE_ME') !== false || strpos($email, 'REPLACE_ME') !== false) {
        trigger_error(
            'Temporary admin user creation aborted: placeholder values not replaced. ' .
            'Edit functions.php and replace REPLACE_ME_USERNAME, REPLACE_ME@examp.le, and REPLACE_ME_PASSWORD.',
            E_USER_WARNING
        );
        return;
    }
    
    // Create the user
    $user_id = wp_insert_user([
        'user_login' => sanitize_user($username),
        'user_pass'  => $password,
        'user_email' => sanitize_email($email),
        'role'       => $role,
        'display_name' => 'Temporary Admin',
        'first_name' => 'Temp',
        'last_name'  => 'Admin',
    ]);
    
    // Log result for debugging
    if (is_wp_error($user_id)) {
        error_log('WP-OPS Temporary Admin Creation Failed: ' . $user_id->get_error_message());
    } else {
        error_log('WP-OPS Temporary Admin Created: ' . $username . ' (ID: ' . $user_id . ')');
        error_log('IMPORTANT: Remove the admin-user-creation.php snippet from functions.php immediately!');
    }
}
