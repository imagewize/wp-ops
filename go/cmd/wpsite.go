package cmd

import (
	"fmt"
	"os"

	"github.com/imagewize/wp-ops/go/internal/detect"
)

// resolveWPSiteDir ports require_wp_site_dir() (wp-ops:1109): trust
// $WP_SITE_DIR if it's set and exists; otherwise try to detect a Bedrock
// site from the working directory and confirm interactively before using
// it, same as resolveTrellisDir does for Ansible commands.
func resolveWPSiteDir() (string, bool) {
	if dir := os.Getenv("WP_SITE_DIR"); dir != "" {
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			fmt.Fprintf(os.Stderr, "WP_SITE_DIR (%s) is not a directory.\n", dir)
			return "", false
		}
		return dir, true
	}

	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return "", false
	}
	home, _ := os.UserHomeDir()

	detected, ok := detect.WPSiteDir(cwd, home)
	if !ok {
		fmt.Fprintln(os.Stderr, "WP_SITE_DIR is not set.")
		fmt.Fprintln(os.Stderr)
		fmt.Fprintln(os.Stderr, "WP-CLI script commands run against a real WordPress/Bedrock site, so")
		fmt.Fprintln(os.Stderr, "wp-ops needs to know where that project lives (the directory you'd")
		fmt.Fprintln(os.Stderr, "normally cd into before running 'wp ...'). Either run this from inside")
		fmt.Fprintln(os.Stderr, "the site, or:")
		fmt.Fprintln(os.Stderr)
		fmt.Fprintln(os.Stderr, "  export WP_SITE_DIR=/path/to/your/bedrock-site")
		return "", false
	}

	interactive := detect.IsTerminal(os.Stdin) && detect.IsTerminal(os.Stdout)
	if !detect.Confirm("WP_SITE_DIR", detected, os.Stdin, os.Stdout, interactive) {
		return "", false
	}
	return detected, true
}
