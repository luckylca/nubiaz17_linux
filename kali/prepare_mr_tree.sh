#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="${UPSTREAM:-https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernels.git}"
OUT="${1:-/tmp/nx563j-kali-nethunter-kernels-mr}"
BRANCH="${BRANCH:-nx563j-los}"

fail() { echo "[FAIL] $*" >&2; exit 1; }
warn() { echo "[WARN] $*" >&2; }
pass() { echo "[ OK ] $*"; }

[[ ! -e "$OUT" ]] || fail "output already exists: $OUT (remove it explicitly if you want a fresh staging tree)"

"$ROOT/kali/validate_submission.sh"

echo "==> clone current upstream"
for attempt in 1 2 3; do
  # Upstream contains hundreds of prebuilt kernel binaries. For an MR that
  # only edits devices.yml and adds one device directory, avoid fetching all
  # historical blobs: a shallow blobless sparse clone is sufficient.
  if git clone --depth=1 --filter=blob:none --sparse "$UPSTREAM" "$OUT"; then break; fi
  rm -rf "$OUT"
  [[ "$attempt" -lt 3 ]] || fail "unable to clone upstream after 3 attempts"
  sleep "$attempt"
done

git -C "$OUT" switch -c "$BRANCH"

if grep -q '^ *- nx563j:' "$OUT/devices.yml"; then
  fail "upstream already contains nx563j; refresh the port instead of appending a duplicate"
fi

printf '\n' >> "$OUT/devices.yml"
# Keep local review comments in kali/devices.yml.nx563j, but do not copy
# project-local commentary into upstream devices.yml. Append only the YAML entry.
sed -n '/^- nx563j:/,$p' "$ROOT/kali/devices.yml.nx563j" >> "$OUT/devices.yml"
mkdir -p "$OUT/fifteen"
cp -R "$ROOT/kali/fifteen/nx563j-los" "$OUT/fifteen/"

# Fast checks that require no Python packages. New device files are untracked in
# the sparse clone, so plain `git diff --check` would silently ignore them.
# Intent-to-add makes Git inspect their contents without actually staging a
# commit; reset the index immediately afterwards so the staging tree remains a
# clean review workspace with only worktree changes.
git -C "$OUT" add --intent-to-add --sparse devices.yml fifteen/nx563j-los
git -C "$OUT" diff --check
git -C "$OUT" reset --mixed HEAD >/dev/null
if command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -e 'x=YAML.load_file(ARGV[0]); n=x.count{|e| e.is_a?(Hash) && e.key?("nx563j")}; abort("nx563j entries=#{n}") unless n==1' "$OUT/devices.yml"
  pass "merged devices.yml parses and contains exactly one nx563j entry"
else
  warn "ruby unavailable; YAML parse check skipped"
fi

# Run the exact upstream checks when their dependencies are already available.
if command -v yamllint >/dev/null 2>&1; then
  (cd "$OUT" && yamllint devices.yml)
  pass "upstream yamllint PASS"
else
  warn "yamllint not installed; upstream CI will run it"
fi

if python3 -c 'import yaml' >/dev/null 2>&1; then
  # devices-integrity.py validates YAML against android-version/kernel-id path
  # presence. A sparse clone intentionally omits the historical binary trees,
  # so materialize an exact metadata-only directory skeleton from the upstream
  # Git tree and run the unmodified official script there.
  integrity_tmp="$(mktemp -d "${TMPDIR:-/tmp}/nx563j-integrity.XXXXXX")"
  mkdir -p "$integrity_tmp/bin" "$integrity_tmp/example_scripts" "$integrity_tmp/patches"
  cp "$OUT/devices.yml" "$integrity_tmp/devices.yml"
  git -C "$OUT" show HEAD:bin/devices-integrity.py > "$integrity_tmp/bin/devices-integrity.py"
  chmod +x "$integrity_tmp/bin/devices-integrity.py"

  versions="$(git -C "$OUT" ls-tree -d --name-only HEAD | grep -vE '^(.gitlab|bin|example_scripts|patches)$')"
  for d in $versions; do mkdir -p "$integrity_tmp/$d"; done

  git -C "$OUT" ls-tree -d -r --name-only HEAD | awk -F/ 'NF==2{print}' | while IFS= read -r p; do
    first="${p%%/*}"
    if printf '%s\n' "$versions" | grep -Fxq "$first"; then
      mkdir -p "$integrity_tmp/$p"
    fi
  done
  # Real checkouts may use symlinks for version/kernel aliases. os.path.isdir()
  # follows them, so represent depth-2 symlink aliases as directories too.
  git -C "$OUT" ls-tree -r HEAD | awk '$1=="120000"{print $4}' | awk -F/ 'NF==2{print}' | while IFS= read -r p; do
    mkdir -p "$integrity_tmp/$p"
  done
  mkdir -p "$integrity_tmp/fifteen/nx563j-los"

  err="$integrity_tmp/.nx563j-integrity.stderr"
  (cd "$integrity_tmp" && python3 ./bin/devices-integrity.py >/dev/null 2>"$err")
  if [[ -s "$err" ]]; then
    cat "$err" >&2
    rm -rf "$integrity_tmp"
    fail "upstream devices-integrity.py emitted errors"
  fi
  rm -rf "$integrity_tmp"
  pass "upstream devices-integrity.py PASS (Git-tree metadata skeleton)"
else
  warn "PyYAML not installed; upstream devices-integrity.py check skipped locally"
fi

printf '\n==> MR staging tree ready\n'
printf 'path: %s\n' "$OUT"
printf 'branch: %s\n' "$BRANCH"
printf 'upstream base: %s\n' "$(git -C "$OUT" rev-parse HEAD)"
printf '\nChanged files:\n'
git -C "$OUT" status --short
printf '\nReview with: git -C %q diff -- devices.yml fifteen/nx563j-los\n' "$OUT"
printf 'No commit and no push were performed.\n'
