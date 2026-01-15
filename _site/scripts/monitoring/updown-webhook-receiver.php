<?php
/**
 * updown.io Webhook Receiver
 *
 * This script receives webhooks from updown.io and triggers log analysis.
 *
 * Installation:
 * 1. Place this file in a web-accessible directory
 * 2. Configure updown.io to send webhooks to: https://example.com/updown-webhook.php
 * 3. Set WEBHOOK_SECRET to match your updown.io webhook secret
 * 4. Ensure the script has permission to execute the shell script
 *
 * updown.io Webhook Events:
 * - check.down: Site is down
 * - check.up: Site is back up
 * - check.ssl_expiry: SSL certificate expiring soon
 */

// ============================================================================
// Configuration
// ============================================================================

// Set this to match your updown.io webhook secret for security
define('WEBHOOK_SECRET', 'your-webhook-secret-here');

// Path to the handler script
define('HANDLER_SCRIPT', '/home/web/monitoring/updown-webhook-handler.sh');

// Email for alerts (optional)
define('ALERT_EMAIL', '');

// Log file for webhook activity
define('LOG_FILE', '/home/web/monitoring/updown-webhooks.log');

// ============================================================================
// Functions
// ============================================================================

/**
 * Log a message
 */
function logMessage($message) {
    $timestamp = date('Y-m-d H:i:s');
    $logEntry = "[{$timestamp}] {$message}\n";
    file_put_contents(LOG_FILE, $logEntry, FILE_APPEND);
    error_log($logEntry);
}

/**
 * Verify webhook signature (if using signed webhooks)
 */
function verifySignature($payload, $signature) {
    if (empty(WEBHOOK_SECRET)) {
        return true; // Skip verification if no secret configured
    }

    $expectedSignature = hash_hmac('sha256', $payload, WEBHOOK_SECRET);
    return hash_equals($expectedSignature, $signature);
}

/**
 * Parse updown.io webhook payload
 */
function parseWebhook() {
    $payload = file_get_contents('php://input');

    if (empty($payload)) {
        http_response_code(400);
        die('No payload received');
    }

    $data = json_decode($payload, true);

    if (json_last_error() !== JSON_ERROR_NONE) {
        http_response_code(400);
        die('Invalid JSON payload');
    }

    return [
        'payload' => $payload,
        'data' => $data
    ];
}

/**
 * Handle the webhook event
 */
function handleWebhook($data) {
    $event = $data['event'] ?? 'unknown';
    $url = $data['check']['url'] ?? 'unknown';

    // Extract domain from URL
    $domain = parse_url($url, PHP_URL_HOST);

    logMessage("Received webhook: event={$event}, url={$url}");

    // Map updown.io events to our handler script events
    $eventMap = [
        'check.down' => 'down',
        'check.up' => 'up',
        'check.ssl_expiry' => 'ssl',
    ];

    $handlerEvent = $eventMap[$event] ?? null;

    if (!$handlerEvent) {
        logMessage("Unknown event type: {$event}");
        return false;
    }

    // Execute the handler script
    $command = escapeshellcmd(HANDLER_SCRIPT) . ' '
             . escapeshellarg($domain) . ' '
             . escapeshellarg($handlerEvent);

    if (!empty(ALERT_EMAIL)) {
        $command = 'ALERT_EMAIL=' . escapeshellarg(ALERT_EMAIL) . ' ' . $command;
    }

    logMessage("Executing: {$command}");

    // Execute in background
    exec($command . ' > /dev/null 2>&1 &');

    return true;
}

// ============================================================================
// Main Logic
// ============================================================================

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    die('Method not allowed');
}

// Parse webhook
$webhook = parseWebhook();

// Verify signature if provided
$signature = $_SERVER['HTTP_X_UPDOWN_SIGNATURE'] ?? '';
if (!verifySignature($webhook['payload'], $signature)) {
    logMessage("Invalid webhook signature");
    http_response_code(403);
    die('Invalid signature');
}

// Handle the webhook
$success = handleWebhook($webhook['data']);

if ($success) {
    http_response_code(200);
    echo json_encode(['status' => 'success', 'message' => 'Webhook processed']);
} else {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Failed to process webhook']);
}

logMessage("Webhook processed successfully");
