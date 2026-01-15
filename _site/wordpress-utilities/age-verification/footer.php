<?php
/**
 * Age Verification Modal Footer Template
 * 
 * This file contains the HTML structure for the age verification modal.
 * Uses Advanced Custom Fields (ACF) for dynamic content management.
 * Include this in your WordPress theme's footer.php or as a separate template part.
 * 
 * IMPORTANT: Make sure to include modal.css in your theme or copy its styles to your main stylesheet.
 * You can enqueue it in your functions.php:
 * wp_enqueue_style('age-verification-modal', get_template_directory_uri() . '/age-verification/modal.css');
 */

// Ensure ACF is loaded
if ( ! function_exists( 'get_field' ) ) {
    if ( file_exists( WP_PLUGIN_DIR . '/advanced-custom-fields/acf.php' ) ) {
        include_once( WP_PLUGIN_DIR . '/advanced-custom-fields/acf.php' );
    } else {
        // Optionally, display an admin notice or fallback
        error_log('ACF plugin is not active. Please activate Advanced Custom Fields.');
    }
}

// Get ACF button values
$avs_buttons = array(
    'button_1' => function_exists('get_field') ? get_field('avs_button_1', 'option') : '',
    'button_2' => function_exists('get_field') ? get_field('avs_button_2', 'option') : '', 
    'button_3' => function_exists('get_field') ? get_field('avs_button_3', 'option') : ''
);
?>

<!-- Age Verification Modal -->
<div class="modal-verification" id="modal_verification">
  <div class="modal-data-panel">
    <div class="modal-header-panel text-center">

      <?php if (function_exists('get_field') && !empty(get_field('avs_header_logo', 'option'))): ?>
        <div class="modal-logo">
          <img src="<?php echo function_exists('get_field') ? get_field('avs_header_logo', 'option') : ''; ?>" alt="" />
        </div>
      <?php endif; ?>

      <div class="modal-header-data">

        <?php if (function_exists('get_field') && !empty(get_field('avs_heading', 'option'))): ?>
          <h5 style="margin-top: 0;"><?php echo function_exists('get_field') ? get_field('avs_heading', 'option') : ''; ?></h5>
        <?php endif; ?>

        <?php if (function_exists('get_field') && !empty(get_field('avs_subheading', 'option'))): ?>
          <h2 class='h1' style="margin-top: 0; margin-bottom: 10px; font-weight: 500;"><?php echo function_exists('get_field') ? get_field('avs_subheading', 'option') : ''; ?></h2>
        <?php endif; ?>

        <?php if (function_exists('get_field') && !empty(get_field('avs_description', 'option'))): ?>
          <div class="modal-header-content text-base">
            <p><?php echo function_exists('get_field') ? get_field('avs_description', 'option') : ''; ?></p>
          </div>
        <?php endif; ?>

      </div>
    </div>

    <div class="modal-content-panel">

      <?php if (!empty($avs_buttons)): ?>
        <div class="btn-stack">

          <?php if (!empty($avs_buttons['button_1'])): ?>
            <a href="javascript:void(0)" id="under-18" class="btn-default"><?php echo $avs_buttons['button_1']; ?></a>
          <?php endif; ?>

          <?php if (!empty($avs_buttons['button_2'])): ?>
            <a href="javascript:void(0)" id="18-23" class="btn-default"><?php echo $avs_buttons['button_2']; ?></a>
          <?php endif; ?>

          <?php if (!empty($avs_buttons['button_3'])): ?>
            <a href="javascript:void(0)" id="over-24" class="btn-default"><?php echo $avs_buttons['button_3']; ?></a>
          <?php endif; ?>

        </div>
      <?php endif; ?>

      <?php if (function_exists('get_field')): ?>
        <?php $avs_verification_check_text = get_field('avs_verification_check_text', 'option'); ?>
        <?php if (!empty($avs_verification_check_text)): ?>
          <div class="verification-check">
            <div class="form-group">
              <input type="checkbox" checked="checked" name="" id="age_verify" />
              <label for="age_verify"><?php echo $avs_verification_check_text; ?></label>
            </div>
          </div>
        <?php endif; ?>
      <?php endif; ?>

    </div>

    <?php if (function_exists('get_field')): ?>
      <?php $avs_confirmation_text = get_field('avs_confirmation_text', 'option'); ?>
      <?php if (!empty($avs_confirmation_text)): ?>
        <div class="modal-bottom-text text-center">
          <p><?php echo $avs_confirmation_text; ?></p>
        </div>
      <?php endif; ?>
    <?php endif; ?>

  </div>
</div>
<div class="modal-overlayer"></div>

<!-- Example content blocks that will be controlled by the script -->
<!-- Remove these if you don't need them or have your own content structure -->
<!--
<div class="code-block">
    <h3>Casino Highlight Content</h3>
    <p>This content will be hidden for users under 24 or those who opt out.</p>
</div>
-->
