package cmd

import (
	"fmt"
	"os"
	osexec "os/exec"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/detect"
)

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Check dependencies and environment",
	RunE: func(cc *cobra.Command, args []string) error {
		os.Exit(runDoctor())
		return nil
	},
}

func init() {
	rootCmd.AddCommand(doctorCmd)
}

type binCheck struct {
	bin, purpose string
	required     bool
}

type doctorSection struct {
	title string
	bins  []binCheck
}

var doctorSections = []doctorSection{
	{"Core", []binCheck{
		{"git", "version control, release scripts", true},
		{"curl", "redirect checks, 404 checks, webhooks", true},
	}},
	{"WordPress & Trellis", []binCheck{
		{"wp", "WP-CLI scripts (wp-cli/, bedrock/)", false},
		{"ansible-playbook", "Trellis playbooks (trellis/)", false},
		{"trellis", "Trellis CLI", false},
		{"composer", "Bedrock dependency management", false},
	}},
	{"Images & patterns", []binCheck{
		{"magick", "batch resize, trim/center screenshots", false},
		{"cwebp", "WebP conversion", false},
		{"node", "Playwright screenshots, sharp conversion", false},
	}},
	{"Git & release", []binCheck{
		{"gh", "PR creation, releases, traffic stats", false},
		{"svn", "WordPress.org plugin deploys", false},
		{"zip", "packaging plugin/theme release assets", false},
	}},
	{"Remote & sync", []binCheck{
		{"ssh", "remote monitors, screenshots, post counts", false},
		{"rsync", "theme and package sync", false},
	}},
	{"Helpers", []binCheck{
		{"jq", "JSON parsing in several scripts", false},
		{"fzf", "fuzzy command picker in the bash CLI", false},
	}},
}

// runDoctor ports run_doctor (wp-ops:1791).
func runDoctor() int {
	missingRequired := false

	fmt.Println()
	fmt.Printf("wp-ops doctor %s\n\n", getVersion())

	for _, s := range doctorSections {
		fmt.Println(s.title)
		for _, b := range s.bins {
			if !checkBinary(b.bin, b.purpose, b.required) && b.required {
				missingRequired = true
			}
		}
		fmt.Println()
	}

	fmt.Println("Server-side (not checked here — these run on the server)")
	fmt.Println("  ·  gawk               time filtering in the Nginx log monitors")
	fmt.Println("     Ubuntu ships mawk by default, so gawk may be absent:")
	fmt.Println("     check with  ssh web@host 'command -v gawk'")
	fmt.Println()

	fmt.Println("Environment")
	checkEnvDir("TRELLIS_DIR", "needed by trellis/ playbooks", detect.TrellisDir)
	checkEnvDir("WP_SITE_DIR", "needed by wp-cli/ and bedrock/ scripts", detect.WPSiteDir)
	fmt.Println()

	c := mustCatalog()
	fmt.Println("Catalog")
	fmt.Printf("  ✓ %d commands discovered\n", len(c.Entries))
	fmt.Println()

	if missingRequired {
		fmt.Println("✗ Missing a required tool — install it before continuing.")
		return 1
	}
	fmt.Println("✓ Core tools present. Optional ones are only needed by the commands that use them.")
	return 0
}

func checkBinary(bin, purpose string, required bool) bool {
	_, err := osexec.LookPath(bin)
	ok := err == nil

	mark := "!"
	switch {
	case ok:
		mark = "✓"
	case required:
		mark = "✗"
	}
	fmt.Printf("  %s %-18s %s\n", mark, bin, purpose)
	return ok
}

func checkEnvDir(varName, purpose string, detector func(startDir, stopAt string) (string, bool)) {
	value := os.Getenv(varName)
	if value == "" {
		cwd, _ := os.Getwd()
		home, _ := os.UserHomeDir()
		if detected, ok := detector(cwd, home); ok {
			fmt.Printf("  ! %-18s not set — candidate at %s (confirmed per run)\n", varName, detected)
		} else {
			fmt.Printf("  ! %-18s not set — %s\n", varName, purpose)
		}
		return
	}

	info, err := os.Stat(value)
	if err != nil || !info.IsDir() {
		fmt.Printf("  ✗ %-18s %s (not a directory)\n", varName, value)
		return
	}
	fmt.Printf("  ✓ %-18s %s\n", varName, value)
}
