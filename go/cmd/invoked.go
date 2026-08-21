package cmd

import (
	"os"
	"path/filepath"
)

// trellis-cli discovers plugins by scanning $PATH for executables named
// `trellis-*`, then splits the filename on "-", drops the first segment,
// and joins the rest with spaces to form the subcommand (trellis-cli
// plugin/finder.go:62-67). So the binary must be named `trellis-ops` for
// the one-word `trellis ops`: `trellis-wp-ops` would become the
// three-word `trellis wp ops`.
//
// The Homebrew cask ships this name as a second symlink to the same
// binary (.goreleaser.yml, homebrew_casks.custom_block), so wp-ops is
// literally the same executable under both names — which is why the only
// thing distinguishing the two invocations is argv[0].
const trellisPluginBinary = "trellis-ops"

// invokedAs is argv[0]'s basename. A var rather than a func so tests can
// swap it; nothing else should write to it.
var invokedAs = filepath.Base(os.Args[0])

// asTrellisPlugin reports whether we were run as `trellis ops ...` rather
// than as bare `wp-ops ...`.
func asTrellisPlugin() bool { return invokedAs == trellisPluginBinary }

// cmdName is how the user actually typed us, for help text and
// suggestions. Printing "wp-ops <category>" at someone who typed
// "trellis ops" tells them to run a command they may not know exists.
func cmdName() string {
	if asTrellisPlugin() {
		return "trellis ops"
	}
	return "wp-ops"
}

// defaultPlatform scopes the *listing* views when we're running inside
// trellis-cli: someone at a `trellis` prompt wants the 27 commands tagged
// @platform trellis, not the image converters and release scripts. It
// deliberately does not scope *execution* — every command still runs if
// you name it, and an explicit --platform always wins.
func defaultPlatform() string {
	if asTrellisPlugin() {
		return "trellis"
	}
	return ""
}
