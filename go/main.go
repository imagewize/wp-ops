// Command wp-ops discovers and runs the manifest-annotated scripts,
// playbooks, and snippets in this repo. See docs/cli-ux-plan.md at the repo
// root for architecture.
package main

import (
	"fmt"
	"os"

	"github.com/imagewize/wp-ops/go/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
