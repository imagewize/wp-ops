#!/bin/bash
#
# Update a Roots Trellis installation to a newer upstream release without
# losing local customizations.
#
# Instead of copying upstream over trellis/ (which silently reverts every local
# change not on an exclude list), this applies only what upstream changed
# between two releases, as a three-way merge per file:
#
#   base   = the file at the release you are on   (e.g. v1.28.0)
#   theirs = the file at the target release        (e.g. v1.33.0)
#   ours   = your file in trellis/
#
# Local edits, local-only files and playbooks are kept. Upstream fixes you
# already cherry-picked merge cleanly as identical changes. Real overlaps get
# standard conflict markers to resolve in your editor; nothing is overwritten
# without being reported.
#
# The release you are on is read from trellis/VERSION (Trellis >= 1.29). Older
# trees have no VERSION file, so the closest upstream tag is detected by
# comparing files; override with --from when you know better.
#
# The trellis/ directory is taken from $TRELLIS_DIR, the same variable the
# playbook commands use. If it isn't set, this walks up from the current
# directory the way `detect.TrellisDir` does.
#
# Options:
#   --from=<tag>   Release the tree is currently on (default: VERSION file or auto-detect)
#   --to=<tag>     Release to update to (default: latest upstream release tag)
#   --dry-run      Report what would merge, conflict or be skipped; change nothing
#   --yes, -y      Skip the confirmation prompt
#
# @desc     Update Trellis to a newer upstream release via three-way merge, keeping local customizations
# @category misc
# @platform trellis
# @runs     local
# @requires git
# @flag     --from     optional  {tag}  Release the tree is currently on (default: VERSION file or auto-detect)
# @flag     --to       optional  {tag}  Release to update to (default: latest upstream tag)
# @flag     --dry-run  optional  {}     Report what would change without writing anything
# @flag     --yes      optional  {}     Skip the confirmation prompt
# @example  TRELLIS_DIR=~/code/example.com/trellis wp-ops trellis-updater --dry-run
# @example  wp-ops trellis-updater --to=v1.33.0
# @example  wp-ops trellis-updater --from=v1.28.0 --yes

set -euo pipefail

UPSTREAM_URL="https://github.com/roots/trellis.git"

SKIP_CONFIRM=0
DRY_RUN=0
FROM=""
TO=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) SKIP_CONFIRM=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --from=*) FROM="${arg#--from=}" ;;
    --to=*) TO="${arg#--to=}" ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (see --help)" >&2
      exit 1
      ;;
  esac
done

# Upstream paths never merged into a project: CI, tests and upstream docs are
# irrelevant, and the example vault/site/host files don't share history with a
# real project's (vault files are encrypted locally, so a merge is meaningless).
# Upstream changes to the project-config ones are saved for review instead.
SKIP_PATTERNS=(
  ".github/*"
  "tests/*"
  "README.md"
  "CHANGELOG.md"
  "pytest.ini"
  "requirements-dev.txt"
)
REVIEW_ONLY_PATTERNS=(
  "hosts/*"
  "group_vars/*/vault.yml"
  "group_vars/*/wordpress_sites.yml"
)

matches_any() {
  local path="$1"; shift
  local pattern
  for pattern in "$@"; do
    # shellcheck disable=SC2053
    [[ "$path" == $pattern ]] && return 0
  done
  return 1
}

# Walks up from the current directory looking for a Trellis project. Two shapes
# count: the directory *is* trellis/ (ansible.cfg + group_vars/ inside it), or a
# parent holds trellis/ansible.cfg — the latter trusted only when we started in
# that parent, or the directory walked up through is that parent's own Bedrock
# site (web/wp/), so a sibling checkout that merely happens to sit near an
# unrelated trellis/ isn't picked up by accident.
# Same implementation as scripts/backup/db-pull.sh; mirrors
# go/internal/detect.TrellisDir.
detect_trellis_dir() {
    local start="$PWD"
    local dir="$start"
    local previous="$start"

    while [[ -n "$dir" && "$dir" != "/" && "$dir" != "$HOME" ]]; do
        if [[ -f "$dir/ansible.cfg" && -d "$dir/group_vars" ]]; then
            echo "$dir"
            return 0
        fi

        if [[ -f "$dir/trellis/ansible.cfg" ]]; then
            if [[ "$dir" == "$start" || -d "$previous/web/wp" ]]; then
                echo "$dir/trellis"
                return 0
            fi
        fi

        previous="$dir"
        dir="$(dirname "$dir")"
    done

    return 1
}

# Confirms an auto-detected TRELLIS_DIR before using it — this rewrites files
# in trellis/, so a non-interactive session refuses to guess.
# Mirrors go/internal/detect.Confirm.
confirm_trellis_dir() {
    local detected="$1"

    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "TRELLIS_DIR is not set." >&2
        echo "" >&2
        echo "Detected a candidate at $detected, but wp-ops won't assume it" >&2
        echo "non-interactively. Set it explicitly:" >&2
        echo "" >&2
        echo "  export TRELLIS_DIR=$detected" >&2
        echo "" >&2
        return 1
    fi

    echo "TRELLIS_DIR is not set."
    echo "Detected from the current directory: $detected"
    echo ""
    read -p "Use it for this command? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi

    echo "Cancelled. Set it explicitly instead:"
    echo ""
    echo "  export TRELLIS_DIR=/path/to/your/project"
    echo ""
    return 1
}

if [ -z "${TRELLIS_DIR:-}" ]; then
    if detected=$(detect_trellis_dir); then
        confirm_trellis_dir "$detected" || exit 1
        TRELLIS_DIR="$detected"
    else
        echo "ERROR: TRELLIS_DIR is not set and no Trellis project was found." >&2
        echo "  Run this from inside a Trellis project, or set it explicitly:" >&2
        echo "    export TRELLIS_DIR=/path/to/your/trellis" >&2
        exit 1
    fi
fi

if [ ! -f "$TRELLIS_DIR/ansible.cfg" ]; then
  echo "ERROR: $TRELLIS_DIR does not look like a Trellis directory (no ansible.cfg)." >&2
  exit 1
fi
TRELLIS_DIR="$(cd "$TRELLIS_DIR" && pwd)"

# Git is the rollback: refuse to merge into a tree with uncommitted changes, so
# `git diff` afterwards shows exactly what the update did and `git checkout`
# undoes it. Outside git, fall back to a full copy.
IN_GIT=0
if git -C "$TRELLIS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=1
  if [ "$DRY_RUN" -eq 0 ] && [ -n "$(git -C "$TRELLIS_DIR" status --porcelain -- .)" ]; then
    echo "ERROR: $TRELLIS_DIR has uncommitted changes." >&2
    echo "  Commit or stash them first, so the update can be reviewed and undone with git." >&2
    echo "  (Tip: run the update on its own branch.)" >&2
    exit 1
  fi
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/trellis-updater.XXXXXX")"
UPSTREAM="$WORK_DIR/upstream"
REVIEW_DIR=~/trellis-update-$(date +%Y%m%d_%H%M%S)

echo "=== Trellis updater ==="
echo "Trellis dir: $TRELLIS_DIR"
echo ""

echo "=== Fetching upstream Trellis ==="
git clone --quiet "$UPSTREAM_URL" "$UPSTREAM"
up() { git -C "$UPSTREAM" "$@"; }

if [ -z "$TO" ]; then
  TO="$(up tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
fi
up rev-parse --verify --quiet "$TO^{commit}" >/dev/null || { echo "ERROR: unknown upstream tag: $TO" >&2; exit 1; }

# Work out which release the tree is on.
if [ -z "$FROM" ] && [ -f "$TRELLIS_DIR/VERSION" ]; then
  FROM="$(tr -d '[:space:]' < "$TRELLIS_DIR/VERSION")"
  echo "Current release (from VERSION): $FROM"
fi
if [ -z "$FROM" ]; then
  echo "No VERSION file; detecting the closest upstream release (this takes a moment)..."
  best_tag=""; best_count=999999
  results=""
  while read -r tag; do
    count=0
    while read -r path; do
      matches_any "$path" "${SKIP_PATTERNS[@]}" "${REVIEW_ONLY_PATTERNS[@]}" && continue
      if [ ! -f "$TRELLIS_DIR/$path" ] || ! up show "$tag:$path" | cmp -s - "$TRELLIS_DIR/$path"; then
        count=$((count + 1))
      fi
    done < <(up ls-tree -r --name-only "$tag")
    results+="  $tag: $count file(s) differ"$'\n'
    if [ "$count" -lt "$best_count" ]; then best_count=$count; best_tag=$tag; fi
  done < <(up tag --sort=-v:refname | grep -E '^v1\.[0-9]+\.[0-9]+$' | head -12)
  printf "%s" "$results"
  FROM="$best_tag"
  echo "Closest release: $FROM ($best_count differing files). Override with --from=<tag> if this is wrong."
fi
up rev-parse --verify --quiet "$FROM^{commit}" >/dev/null || { echo "ERROR: unknown upstream tag: $FROM" >&2; exit 1; }
echo "Updating: $FROM -> $TO"
echo ""

if [ "$(up rev-parse "$FROM^{commit}")" = "$(up rev-parse "$TO^{commit}")" ]; then
  echo "Already on $TO. Nothing to do."
  rm -rf "$WORK_DIR"
  exit 0
fi

if [ "$IN_GIT" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$REVIEW_DIR"
  cp -R "$TRELLIS_DIR" "$REVIEW_DIR/trellis-backup"
  echo "Not a git checkout: backed up to $REVIEW_DIR/trellis-backup"
  echo ""
fi

# Classify every upstream change between the two releases.
MERGED=(); CONFLICTS=(); ADDED=(); DELETED=(); CURRENT=(); KEPT=(); REVIEW=()
BASE_F="$WORK_DIR/base"; THEIRS_F="$WORK_DIR/theirs"; OUT_F="$WORK_DIR/out"
mkdir -p "$WORK_DIR/results"

while IFS=$'\t' read -r status path; do
  matches_any "$path" "${SKIP_PATTERNS[@]}" && continue
  if matches_any "$path" "${REVIEW_ONLY_PATTERNS[@]}"; then
    REVIEW+=("$path"); continue
  fi
  local_f="$TRELLIS_DIR/$path"

  case "$status" in
    M)
      if [ ! -f "$local_f" ]; then KEPT+=("$path (changed upstream, absent locally)"); continue; fi
      up show "$FROM:$path" > "$BASE_F"
      up show "$TO:$path" > "$THEIRS_F"
      rc=0
      git merge-file -p -L local -L "$FROM" -L "$TO" "$local_f" "$BASE_F" "$THEIRS_F" > "$OUT_F" || rc=$?
      if [ "$rc" -lt 0 ] || [ "$rc" -gt 127 ]; then echo "ERROR: merge failed for $path" >&2; exit 1; fi
      if [ "$rc" -gt 0 ]; then
        CONFLICTS+=("$path ($rc conflict(s))")
      elif cmp -s "$OUT_F" "$local_f"; then
        CURRENT+=("$path"); continue
      else
        MERGED+=("$path")
      fi
      if [ "$DRY_RUN" -eq 0 ]; then cat "$OUT_F" > "$local_f"; fi
      ;;
    A)
      up show "$TO:$path" > "$THEIRS_F"
      if [ ! -e "$local_f" ]; then
        ADDED+=("$path")
        if [ "$DRY_RUN" -eq 0 ]; then
          mkdir -p "$(dirname "$local_f")"
          cp "$THEIRS_F" "$local_f"
          if [ "$(up ls-tree "$TO" -- "$path" | cut -c1-6)" = "100755" ]; then chmod +x "$local_f"; fi
        fi
      elif cmp -s "$THEIRS_F" "$local_f"; then
        CURRENT+=("$path")
      else
        : > "$BASE_F"
        rc=0
        git merge-file -p -L local -L "(none)" -L "$TO" "$local_f" "$BASE_F" "$THEIRS_F" > "$OUT_F" || rc=$?
        CONFLICTS+=("$path (added upstream, differs from local copy)")
        if [ "$DRY_RUN" -eq 0 ]; then cat "$OUT_F" > "$local_f"; fi
      fi
      ;;
    D)
      [ -e "$local_f" ] || continue
      if up show "$FROM:$path" | cmp -s - "$local_f"; then
        DELETED+=("$path")
        if [ "$DRY_RUN" -eq 0 ]; then
          rm -f "$local_f"
          # Drop directories the delete emptied (e.g. a removed role).
          d="$(dirname "$local_f")"
          while [ "$d" != "$TRELLIS_DIR" ] && rmdir "$d" 2>/dev/null; do d="$(dirname "$d")"; done
        fi
      else
        KEPT+=("$path (removed upstream, modified locally: delete or keep by hand)")
      fi
      ;;
  esac
done < <(up diff --name-status --no-renames "$FROM" "$TO")

# Upstream changes to project-config files are saved, never applied.
if [ "${#REVIEW[@]}" -gt 0 ]; then
  mkdir -p "$REVIEW_DIR"
  for path in "${REVIEW[@]}"; do
    up diff "$FROM" "$TO" -- "$path" > "$REVIEW_DIR/$(echo "$path" | tr '/' '_').diff"
  done
fi

print_list() {
  local title="$1"; shift
  [ "$#" -eq 0 ] && return 0
  echo "$title ($#):"
  local item
  for item in "$@"; do echo "  $item"; done
  echo ""
}

echo "=== $( [ "$DRY_RUN" -eq 1 ] && echo "Dry run: would apply" || echo "Applied" ) $FROM -> $TO ==="
print_list "Merged cleanly" ${MERGED[@]+"${MERGED[@]}"}
print_list "Added" ${ADDED[@]+"${ADDED[@]}"}
print_list "Deleted (unchanged locally)" ${DELETED[@]+"${DELETED[@]}"}
print_list "Already up to date (e.g. cherry-picked before)" ${CURRENT[@]+"${CURRENT[@]}"}
print_list "CONFLICTS — resolve the <<<<<<< markers" ${CONFLICTS[@]+"${CONFLICTS[@]}"}
print_list "Left alone — decide by hand" ${KEPT[@]+"${KEPT[@]}"}
if [ "${#REVIEW[@]}" -gt 0 ]; then
  print_list "Project config changed upstream (not applied; diffs in $REVIEW_DIR)" "${REVIEW[@]}"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: nothing was changed."
  rm -rf "$WORK_DIR"
  exit 0
fi

# Confirm *after* showing the plan would mean merging twice; the tree is clean
# in git, so asking here and undoing with git is equivalent and simpler.
if [ "$SKIP_CONFIRM" -eq 0 ]; then
  read -p "Keep these changes? (y/N = undo) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    if [ "$IN_GIT" -eq 1 ]; then
      git -C "$TRELLIS_DIR" checkout -q -- .
      git -C "$TRELLIS_DIR" clean -fdq -- .
      echo "Undone. trellis/ is back to its committed state."
    else
      rm -rf "$TRELLIS_DIR" && cp -R "$REVIEW_DIR/trellis-backup" "$TRELLIS_DIR"
      echo "Undone from the backup in $REVIEW_DIR/trellis-backup."
    fi
    rm -rf "$WORK_DIR"
    exit 1
  fi
fi

# Post-merge checks.
echo "=== Checks ==="
HAS_CONFLICTS=0
if grep -rqE --include='*.yml' --include='*.j2' --include='*.cfg' --include='*.py' '^(<<<<<<<|>>>>>>>) ' "$TRELLIS_DIR" 2>/dev/null; then
  HAS_CONFLICTS=1
  echo "⚠ Conflict markers present. Resolve them before provisioning:"
  grep -rlE --include='*.yml' --include='*.j2' --include='*.cfg' --include='*.py' '^(<<<<<<<|>>>>>>>) ' "$TRELLIS_DIR" | sed "s#^$TRELLIS_DIR/#  #"
fi
for f in .vault_pass ansible.cfg; do
  if [ ! -f "$TRELLIS_DIR/$f" ]; then echo "⚠ $f is missing"; fi
done

if up diff --quiet "$FROM" "$TO" -- galaxy.yml; then
  :
else
  echo "galaxy.yml changed: installing Galaxy roles..."
  if command -v trellis >/dev/null 2>&1; then
    if (cd "$TRELLIS_DIR" && trellis galaxy install >/dev/null 2>&1); then
      echo "✓ Galaxy roles installed"
    else
      echo "⚠ trellis galaxy install failed: run it by hand"
    fi
  else
    echo "  Run: cd $TRELLIS_DIR && ansible-galaxy install -r galaxy.yml --force"
  fi
fi

ANSIBLE_PLAYBOOK="$TRELLIS_DIR/.trellis/virtualenv/bin/ansible-playbook"
command -v "$ANSIBLE_PLAYBOOK" >/dev/null 2>&1 || ANSIBLE_PLAYBOOK="$(command -v ansible-playbook || true)"
if [ "$HAS_CONFLICTS" -eq 1 ]; then
  echo "Skipping playbook --syntax-check until the conflicts are resolved."
elif [ -n "$ANSIBLE_PLAYBOOK" ]; then
  for pb in server.yml deploy.yml dev.yml; do
    [ -f "$TRELLIS_DIR/$pb" ] || continue
    if (cd "$TRELLIS_DIR" && "$ANSIBLE_PLAYBOOK" "$pb" --syntax-check -e env=development -e site=example.com >/dev/null 2>&1); then
      echo "✓ $pb syntax OK"
    else
      echo "⚠ $pb failed --syntax-check: run it by hand to see why"
    fi
  done
fi
echo ""

echo "=== Next steps ==="
echo "1. Read the upstream release notes for $FROM..$TO (breaking variable renames, defaults"
echo "   that change on existing servers): https://github.com/roots/trellis/releases"
echo "2. Review the result:   git -C $TRELLIS_DIR diff"
echo "3. Provision development and test, then commit on a branch and provision production."
rm -rf "$WORK_DIR"
