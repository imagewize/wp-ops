#!/usr/bin/env bash
# Parity check between the bash wp-ops CLI and the Go rewrite (go/wp-ops).
#
# Not a permanent test suite — an M3 acceptance check per
# docs/m3-go-skeleton.md, task 8. Diffs `--json` field-for-field (the
# contract other tooling depends on) and does a looser count-based
# comparison for `search`/`doctor`, whose bash output is hand-formatted
# prose rather than a stable contract.
#
# Usage (from the repo root):
#   cd go && go generate ./... && go build -o wp-ops . && cd ..
#   ./go/scripts/parity-check.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASH_CLI="${REPO_ROOT}/wp-ops"
GO_CLI="${REPO_ROOT}/go/wp-ops"

if [[ ! -x "$GO_CLI" ]]; then
    echo "Go binary not found at $GO_CLI — build it first:"
    echo "  cd go && go generate ./... && go build -o wp-ops ."
    exit 1
fi

pass=0
fail=0

check() {
    local name="$1" rc="$2"
    if [[ "$rc" -eq 0 ]]; then
        echo "  PASS  $name"
        pass=$((pass + 1))
    else
        echo "  FAIL  $name"
        fail=$((fail + 1))
    fi
}

echo "== --json list =="
bash_json=$("$BASH_CLI" --json)
go_json=$("$GO_CLI" --json)

json_rc=0
python3 - "$bash_json" "$go_json" <<'PY' || json_rc=$?
import json, sys

bash_data = json.loads(sys.argv[1])
go_data = json.loads(sys.argv[2])

def key(e):
    return e["command"]

bash_by_key = {key(e): e for e in bash_data}
go_by_key = {key(e): e for e in go_data}

missing_in_go = sorted(set(bash_by_key) - set(go_by_key))
extra_in_go = sorted(set(go_by_key) - set(bash_by_key))
if missing_in_go:
    print("Missing in Go catalog:", missing_in_go)
if extra_in_go:
    print("Extra in Go catalog:", extra_in_go)

mismatches = []
for k in sorted(set(bash_by_key) & set(go_by_key)):
    if bash_by_key[k] != go_by_key[k]:
        mismatches.append((k, bash_by_key[k], go_by_key[k]))

if mismatches:
    print(f"{len(mismatches)} field mismatch(es):")
    for k, b, g in mismatches[:20]:
        print(f"  {k}:")
        print(f"    bash: {b}")
        print(f"    go:   {g}")

print(f"bash: {len(bash_data)} commands, go: {len(go_data)} commands")
sys.exit(0 if not (missing_in_go or extra_in_go or mismatches) else 1)
PY
check "--json list matches field-for-field" "$json_rc"

echo ""
echo "== search =="
for term in backup redirect webp database security monitor; do
    bash_count=$("$BASH_CLI" search "$term" 2>/dev/null | grep -c '^  ')
    go_count=$("$GO_CLI" search "$term" 2>/dev/null | grep -c '^  ')
    if [[ "$bash_count" == "$go_count" ]]; then
        check "search '$term' ($bash_count results)" 0
    else
        check "search '$term' (bash=$bash_count go=$go_count)" 1
    fi
done

echo ""
echo "== doctor =="
bash_doctor=$("$BASH_CLI" doctor 2>&1)
go_doctor=$("$GO_CLI" doctor 2>&1)
bash_missing=$(echo "$bash_doctor" | grep -c '✗')
go_missing=$(echo "$go_doctor" | grep -c '✗')
if [[ "$bash_missing" == "$go_missing" ]]; then
    check "doctor required-tool failures match ($bash_missing)" 0
else
    check "doctor required-tool failures (bash=$bash_missing go=$go_missing)" 1
fi

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
