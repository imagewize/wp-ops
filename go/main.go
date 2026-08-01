// Command wp-ops is a Go rewrite of the bash wp-ops CLI wrapper. It reads the
// same manifest-annotated scripts as the bash version; see
// docs/m3-go-skeleton.md at the repo root for scope and status.
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
