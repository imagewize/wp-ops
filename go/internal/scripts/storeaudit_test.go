// Package scripts holds tests that run shipped shell scripts end to end.
package scripts

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

const (
	testUser     = "auditor"
	testPassword = "abcd efgh ijkl mnop"
	testSession  = "session-123"
)

// fakeMin stands in for Min's MCP endpoint: it speaks just enough JSON-RPC
// (initialize, notifications, tools/call) and records which tools were called.
type fakeMin struct {
	t       *testing.T
	srv     *httptest.Server
	mu      sync.Mutex
	called  []string
	results map[string]any // tool name -> structuredContent
	toolErr map[string]string
	sse     bool
	noSess  bool
	status  int // forced HTTP status when non-zero
}

func newFakeMin(t *testing.T) *fakeMin {
	f := &fakeMin{t: t, results: map[string]any{}, toolErr: map[string]string{}}
	f.srv = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeMin) handle(w http.ResponseWriter, r *http.Request) {
	if f.status != 0 {
		w.WriteHeader(f.status)
		return
	}
	want := "Basic " + base64.StdEncoding.EncodeToString([]byte(testUser+":"+testPassword))
	if r.Header.Get("Authorization") != want {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	var req struct {
		ID     *int   `json:"id"`
		Method string `json:"method"`
		Params struct {
			Name      string            `json:"name"`
			Arguments map[string]string `json:"arguments"`
		} `json:"params"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	switch req.Method {
	case "initialize":
		if !f.noSess {
			w.Header().Set("Mcp-Session-Id", testSession)
		}
		f.reply(w, req.ID, map[string]any{"protocolVersion": "2025-06-18"})
	case "notifications/initialized":
		w.WriteHeader(http.StatusAccepted)
	case "tools/call":
		if r.Header.Get("Mcp-Session-Id") != testSession {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		f.mu.Lock()
		f.called = append(f.called, req.Params.Name)
		f.mu.Unlock()
		if msg, ok := f.toolErr[req.Params.Name]; ok {
			f.reply(w, req.ID, map[string]any{
				"isError": true,
				"content": []map[string]string{{"type": "text", "text": msg}},
			})
			return
		}
		f.reply(w, req.ID, map[string]any{"structuredContent": f.results[req.Params.Name]})
	default:
		w.WriteHeader(http.StatusBadRequest)
	}
}

func (f *fakeMin) reply(w http.ResponseWriter, id *int, result any) {
	body, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
	if f.sse {
		w.Header().Set("Content-Type", "text/event-stream")
		fmt.Fprintf(w, "event: message\ndata: %s\n\n", body)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(body)
}

// report builds the slice of Min's report the script reads.
func report(grade string, score int, checks map[string][2]string) map[string]any {
	c := map[string]any{}
	for id, v := range checks {
		c[id] = map[string]string{"status": v[0], "evidence": v[1]}
	}
	return map[string]any{
		"aeo":           map[string]any{"grade": grade, "score": score, "checks": c},
		"service_match": "schema",
		"meta":          map[string]any{"product_found": true},
		"actions":       []map[string]string{{"check": "truth_check", "status": "fail", "service": "schema", "en": "Fix the price"}},
	}
}

type outcome struct {
	stdout, stderr string
	code           int
}

func run(t *testing.T, f *fakeMin, env []string, args ...string) outcome {
	t.Helper()
	for _, tool := range []string{"curl", "jq"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("%s not installed", tool)
		}
	}
	script, err := filepath.Abs("../../../scripts/monitoring/store-audit.sh")
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", append([]string{script}, args...)...)
	cmd.Env = append(os.Environ(),
		"WP_OPS_MIN_MCP_USER="+testUser,
		"WP_OPS_MIN_MCP_PASSWORD="+testPassword,
		"WP_OPS_MIN_MCP_URL="+f.srv.URL,
		"GITHUB_STEP_SUMMARY=",
	)
	cmd.Env = append(cmd.Env, env...)
	var stdout, stderr strings.Builder
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	code := 0
	if err := cmd.Run(); err != nil {
		ee, ok := err.(*exec.ExitError)
		if !ok {
			t.Fatal(err)
		}
		code = ee.ExitCode()
	}
	return outcome{stdout.String(), stderr.String(), code}
}

func standard(f *fakeMin) {
	f.results["min-audit-store"] = report("A", 96, map[string][2]string{"caching": {"pass", ""}})
	f.results["min-audit-product"] = report("B", 83, map[string][2]string{
		"truth_check": {"fail", "JSON-LD says 49.00, the shop says 39.00"},
		"caching":     {"warn", "No page-caching signal"},
		"llms_txt":    {"pass", ""},
	})
	f.results["min-audit-speed"] = map[string]any{"performance": map[string]any{"grade": "C", "score": 61}}
}

const shop = "https://shop.example"

func TestReportOnlyExitsZeroAndUsesProductGrade(t *testing.T) {
	f := newFakeMin(t)
	standard(f)
	o := run(t, f, nil, shop)
	if o.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", o.code, o.stderr)
	}
	// The product step returns the refreshed report, so its grade (B) wins over the first (A).
	for _, want := range []string{"grade B (83/100)", "FAIL  truth_check: JSON-LD says 49.00", "warn  caching", "[schema] Fix the price"} {
		if !strings.Contains(o.stdout, want) {
			t.Errorf("stdout missing %q:\n%s", want, o.stdout)
		}
	}
	if got := strings.Join(f.called, ","); got != "min-audit-store,min-audit-product" {
		t.Errorf("tools called = %s", got)
	}
	// Failures are listed before warnings.
	if strings.Index(o.stdout, "FAIL  truth_check") > strings.Index(o.stdout, "warn  caching") {
		t.Errorf("fail should sort before warn:\n%s", o.stdout)
	}
}

func TestFailUnder(t *testing.T) {
	cases := []struct {
		threshold string
		want      int
	}{{"A", 2}, {"B", 0}, {"C", 0}, {"b", 0}}
	for _, c := range cases {
		f := newFakeMin(t)
		standard(f) // final grade B
		o := run(t, f, nil, "--fail-under", c.threshold, shop)
		if o.code != c.want {
			t.Errorf("--fail-under %s: exit = %d, want %d\n%s", c.threshold, o.code, c.want, o.stdout+o.stderr)
		}
		if c.want == 2 && !strings.Contains(o.stdout, "GATE FAILED") {
			t.Errorf("--fail-under %s: no GATE FAILED block:\n%s", c.threshold, o.stdout)
		}
	}
}

func TestFailOn(t *testing.T) {
	cases := []struct {
		list string
		want int
	}{
		{"truth_check", 2},           // status fail
		{"caching", 2},               // status warn also trips a named check
		{"llms_txt", 0},              // passing
		{"not_a_check", 0},           // unknown id is ignored
		{"llms_txt, truth_check", 2}, // list with spaces
	}
	for _, c := range cases {
		f := newFakeMin(t)
		standard(f)
		o := run(t, f, nil, "--fail-on", c.list, shop)
		if o.code != c.want {
			t.Errorf("--fail-on %q: exit = %d, want %d\n%s", c.list, o.code, c.want, o.stdout+o.stderr)
		}
	}
}

func TestJSONOutput(t *testing.T) {
	f := newFakeMin(t)
	standard(f)
	o := run(t, f, nil, "--json", "--fail-under", "A", shop)
	if o.code != 2 {
		t.Fatalf("exit = %d, want 2", o.code)
	}
	if strings.Contains(o.stderr, "Auditing") {
		t.Errorf("--json should not print progress:\n%s", o.stderr)
	}
	var got struct {
		Grade       string   `json:"grade"`
		GateFailed  bool     `json:"gate_failed"`
		GateReasons []string `json:"gate_reasons"`
		Failing     []struct {
			ID, Status string
		} `json:"failing"`
	}
	if err := json.Unmarshal([]byte(o.stdout), &got); err != nil {
		t.Fatalf("stdout is not JSON: %v\n%s", err, o.stdout)
	}
	if got.Grade != "B" || !got.GateFailed || len(got.GateReasons) != 1 || len(got.Failing) != 2 {
		t.Errorf("unexpected result: %+v", got)
	}
}

func TestJSONOutputWithoutGateHasNoReasons(t *testing.T) {
	f := newFakeMin(t)
	standard(f)
	o := run(t, f, nil, "--json", shop)
	var got struct {
		GateFailed  bool     `json:"gate_failed"`
		GateReasons []string `json:"gate_reasons"`
	}
	if err := json.Unmarshal([]byte(o.stdout), &got); err != nil {
		t.Fatalf("stdout is not JSON: %v\n%s", err, o.stdout)
	}
	if o.code != 0 || got.GateFailed || len(got.GateReasons) != 0 {
		t.Errorf("exit %d, %+v", o.code, got)
	}
}

func TestSpeedAndNoProductSelectTools(t *testing.T) {
	f := newFakeMin(t)
	standard(f)
	o := run(t, f, nil, "--speed", shop)
	if o.code != 0 || !strings.Contains(o.stdout, "Speed (PageSpeed): C (61)") {
		t.Fatalf("exit %d\n%s%s", o.code, o.stdout, o.stderr)
	}
	if got := strings.Join(f.called, ","); got != "min-audit-store,min-audit-product,min-audit-speed" {
		t.Errorf("tools called = %s", got)
	}

	f = newFakeMin(t)
	standard(f)
	o = run(t, f, nil, "--no-product", shop)
	if got := strings.Join(f.called, ","); got != "min-audit-store" {
		t.Errorf("tools called = %s", got)
	}
	// Without the product step the first report stands.
	if !strings.Contains(o.stdout, "grade A (96/100)") {
		t.Errorf("want the audit-store grade:\n%s", o.stdout)
	}
}

func TestServerSentEventsReply(t *testing.T) {
	f := newFakeMin(t)
	standard(f)
	f.sse = true
	o := run(t, f, nil, shop)
	if o.code != 0 || !strings.Contains(o.stdout, "grade B (83/100)") {
		t.Errorf("exit %d\n%s%s", o.code, o.stdout, o.stderr)
	}
}

func TestTextContentFallback(t *testing.T) {
	// A server without structuredContent puts the JSON in the text block.
	f := newFakeMin(t)
	standard(f)
	body, _ := json.Marshal(f.results["min-audit-store"])
	f.results["min-audit-store"] = nil
	f.srv.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			ID     *int                  `json:"id"`
			Method string                `json:"method"`
			Params struct{ Name string } `json:"params"`
		}
		dec := json.NewDecoder(r.Body)
		_ = dec.Decode(&req)
		switch {
		case req.Method == "initialize":
			w.Header().Set("Mcp-Session-Id", testSession)
			f.reply(w, req.ID, map[string]any{})
		case req.Method == "tools/call" && req.Params.Name == "min-audit-store":
			f.reply(w, req.ID, map[string]any{"content": []map[string]string{{"type": "text", "text": string(body)}}})
		case req.Method == "tools/call":
			f.reply(w, req.ID, map[string]any{"structuredContent": f.results[req.Params.Name]})
		default:
			w.WriteHeader(http.StatusAccepted)
		}
	})
	o := run(t, f, nil, "--no-product", shop)
	if o.code != 0 || !strings.Contains(o.stdout, "grade A (96/100)") {
		t.Errorf("exit %d\n%s%s", o.code, o.stdout, o.stderr)
	}
}

func TestErrorsExitOne(t *testing.T) {
	t.Run("bad credentials", func(t *testing.T) {
		f := newFakeMin(t)
		standard(f)
		o := run(t, f, []string{"WP_OPS_MIN_MCP_PASSWORD=wrong"}, shop)
		if o.code != 1 || !strings.Contains(o.stderr, "rejected the credentials") {
			t.Errorf("exit %d\n%s", o.code, o.stderr)
		}
	})
	t.Run("server error", func(t *testing.T) {
		f := newFakeMin(t)
		f.status = http.StatusInternalServerError
		o := run(t, f, nil, shop)
		if o.code != 1 || !strings.Contains(o.stderr, "HTTP 500") {
			t.Errorf("exit %d\n%s", o.code, o.stderr)
		}
	})
	t.Run("no session issued", func(t *testing.T) {
		f := newFakeMin(t)
		standard(f)
		f.noSess = true
		o := run(t, f, nil, shop)
		if o.code != 1 || !strings.Contains(o.stderr, "MCP session") {
			t.Errorf("exit %d\n%s", o.code, o.stderr)
		}
	})
	t.Run("tool reports an error", func(t *testing.T) {
		f := newFakeMin(t)
		standard(f)
		f.toolErr["min-audit-store"] = "Daily audit limit reached. Try again tomorrow."
		o := run(t, f, nil, "--fail-under", "F", shop)
		if o.code != 1 || !strings.Contains(o.stderr, "Daily audit limit reached") {
			t.Errorf("exit %d\n%s", o.code, o.stderr)
		}
		if len(f.called) != 1 {
			t.Errorf("chain should stop after audit-store, called %v", f.called)
		}
	})
	t.Run("unreachable", func(t *testing.T) {
		f := newFakeMin(t)
		f.srv.Close()
		o := run(t, f, nil, shop)
		if o.code != 1 || !strings.Contains(o.stderr, "could not reach") {
			t.Errorf("exit %d\n%s", o.code, o.stderr)
		}
	})
}

func TestUsageErrorsExitOne(t *testing.T) {
	f := newFakeMin(t)
	standard(f)
	cases := map[string][]string{
		"no url":         {},
		"bad scheme":     {"ftp://shop.example"},
		"bad grade":      {"--fail-under", "Z", shop},
		"unknown option": {"--nope", shop},
		"two urls":       {shop, "https://other.example"},
	}
	for name, args := range cases {
		if o := run(t, f, nil, args...); o.code != 1 {
			t.Errorf("%s: exit = %d, want 1\n%s", name, o.code, o.stderr)
		}
	}
	if len(f.called) != 0 {
		t.Errorf("usage errors must not call the server, called %v", f.called)
	}
	o := run(t, f, []string{"WP_OPS_MIN_MCP_USER="}, shop)
	if o.code != 1 || !strings.Contains(o.stderr, "WP_OPS_MIN_MCP_USER") {
		t.Errorf("missing credentials: exit %d\n%s", o.code, o.stderr)
	}
}

func TestPasswordNeverOnCommandLine(t *testing.T) {
	// The script hands curl the auth header through a file, so the secret must not
	// appear in any argv. Check the script text for the one place it is read.
	script, err := os.ReadFile("../../../scripts/monitoring/store-audit.sh")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(script), "-u \"$WP_OPS") || strings.Contains(string(script), "--user ") {
		t.Error("credentials must not be passed with curl -u/--user")
	}
}
