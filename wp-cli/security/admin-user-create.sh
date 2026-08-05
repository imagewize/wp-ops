#!/usr/bin/env bash
#
# admin-user-create.sh — Create a temporary WordPress administrator via WP-CLI
#
# The command-line replacement for the admin-user-creation.php snippet, which
# asked you to paste credentials into functions.php and remember to delete
# them afterwards. Nothing is written to a file here: the password is
# generated, printed once, and the deletion command is printed with it.
#
# Typical use is regaining access after a lockout — lost admin password, a
# plugin that broke login, an ownership handover with no working account.
#
# Usage: ./admin-user-create.sh [OPTIONS] <username> <email>
#
# Options:
#   --role ROLE        Role to assign (default: administrator)
#   --password PASS    Password to set (default: generated, 24 random bytes)
#   --path PATH        WordPress path for WP-CLI (default: WP-CLI's own default)
#   --host HOST        SSH user@host to run WP-CLI on (default: run locally)
#   --site-path PATH   Site root to cd into on the server; required with --host
#   -h, --help         Show this help
#
# Requires: WP-CLI access to the WordPress installation (locally or over SSH)
#
# Security: the password is printed to your terminal, so it lands in scrollback
# and possibly in your shell's history file if you pass --password yourself.
# Prefer the generated default, and delete the user when you're done.
#
# @desc     Create a temporary WordPress administrator with a generated password
# @category security
# @platform wordpress
# @runs     local
# @requires wp
# @arg      username  required  {temp_admin}  Username for the new administrator
# @arg      email     required  {temp@example.com}  Email address for the new administrator
# @flag     --role       optional  {administrator}  Role to assign
# @flag     --password   optional  Password to set (default: generated)
# @flag     --path       optional  {web/wp}  WordPress path for WP-CLI
# @flag     --host       optional  {web@example.com}  SSH user@host to run WP-CLI on
# @flag     --site-path  optional  {/var/www/example.com}  Site root on the server, required with --host
# @example  wp-ops admin-user-create temp_admin temp@example.com
# @example  wp-ops admin-user-create --path web/wp recovery recovery@example.com
# @doc      docs/wordpress-utilities/snippets/admin-user-creation-wpcli.md

set -euo pipefail

ROLE="administrator"
PASSWORD=""
WP_PATH=""
SSH_HOST=""
SITE_PATH=""
USERNAME=""
EMAIL=""

usage() {
    echo "Usage: $(basename "$0") [OPTIONS] <username> <email>"
    echo ""
    echo "Options:"
    echo "  --role ROLE        Role to assign (default: administrator)"
    echo "  --password PASS    Password to set (default: generated)"
    echo "  --path PATH        WordPress path for WP-CLI"
    echo "  --host HOST        SSH user@host to run WP-CLI on"
    echo "  --site-path PATH   Site root to cd into on the server (with --host)"
    echo "  -h, --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") temp_admin temp@example.com"
    echo "  $(basename "$0") --path web/wp recovery recovery@example.com"
    echo "  $(basename "$0") --host web@example.com --site-path /var/www/example.com temp_admin temp@example.com"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --role)      ROLE="$2"; shift 2 ;;
        --password)  PASSWORD="$2"; shift 2 ;;
        --path)      WP_PATH="$2"; shift 2 ;;
        --host)      SSH_HOST="$2"; shift 2 ;;
        --site-path) SITE_PATH="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        -*)          echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            if [ -z "$USERNAME" ]; then
                USERNAME="$1"
            elif [ -z "$EMAIL" ]; then
                EMAIL="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$USERNAME" ] || [ -z "$EMAIL" ]; then
    usage >&2
    exit 1
fi

if [ -n "$SSH_HOST" ] && [ -z "$SITE_PATH" ]; then
    # Deliberately not defaulted to /srv/www/<host>/current the way the
    # Trellis-shaped scripts do — this command is meant to work against any
    # WordPress install, and guessing a Trellis layout is what made those
    # scripts @platform trellis in the first place.
    echo "Error: --site-path is required with --host (the directory to cd into on the server)." >&2
    exit 1
fi

# wp_run invokes WP-CLI locally or over SSH. The --path flag is appended only
# when set, so a plain install (Valet, Herd, public_html) runs with WP-CLI's
# own defaults rather than being forced into Bedrock's web/wp layout.
wp_run() {
    if [ -n "$SSH_HOST" ]; then
        local quoted="" arg
        for arg in "$@"; do quoted+=" $(printf '%q' "$arg")"; done
        if [ -n "$WP_PATH" ]; then quoted+=" $(printf '%q' "--path=$WP_PATH")"; fi
        ssh "$SSH_HOST" "cd $(printf '%q' "$SITE_PATH") && wp$quoted"
    elif [ -n "$WP_PATH" ]; then
        wp "$@" --path="$WP_PATH"
    else
        wp "$@"
    fi
}

echo "Checking for an existing user..."

if wp_run user get "$USERNAME" --field=ID >/dev/null 2>&1; then
    echo "Error: a user named '$USERNAME' already exists." >&2
    echo "Pick another username, or inspect it with: wp user get $USERNAME" >&2
    exit 1
fi

if wp_run user get "$EMAIL" --field=ID >/dev/null 2>&1; then
    echo "Error: a user with email '$EMAIL' already exists." >&2
    echo "Pick another address, or inspect it with: wp user get $EMAIL" >&2
    exit 1
fi

GENERATED=0
if [ -z "$PASSWORD" ]; then
    if ! command -v openssl >/dev/null 2>&1; then
        echo "Error: openssl not found — pass --password explicitly." >&2
        exit 1
    fi
    PASSWORD=$(openssl rand -base64 24)
    GENERATED=1
fi

echo "Creating '$USERNAME' with role '$ROLE'..."

if ! wp_run user create "$USERNAME" "$EMAIL" \
        --role="$ROLE" \
        --user_pass="$PASSWORD" \
        --display_name="Temporary Admin" \
        --porcelain >/dev/null; then
    echo "Error: WP-CLI could not create the user." >&2
    exit 1
fi

echo ""
echo "User created."
echo ""
echo "  Username: $USERNAME"
echo "  Email:    $EMAIL"
echo "  Role:     $ROLE"
if [ "$GENERATED" -eq 1 ]; then
    echo "  Password: $PASSWORD"
    echo ""
    echo "The password is shown once and is not stored anywhere. Copy it now."
fi
echo ""
echo "Delete this user when you no longer need it:"
if [ -n "$SSH_HOST" ]; then
    echo "  ssh $SSH_HOST \"cd $SITE_PATH && wp user delete $USERNAME --yes --reassign=1\""
else
    echo "  wp user delete $USERNAME --yes --reassign=1${WP_PATH:+ --path=$WP_PATH}"
fi
