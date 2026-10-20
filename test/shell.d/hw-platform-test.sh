#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

detector="$ROOT/bin/omarchy-hw-platform"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# Detect the platform on x86 workstation.
actual=$("$detector") || fail "omarchy-hw-platform runs successfully"
[[ $actual == "x86" ]] || fail "omarchy-hw-platform outputs x86" "actual: $actual"
pass "omarchy-hw-platform identifies the x86 workstation"

# omarchy-hw-x86 predicate confirms x86_64 CPU.
"$ROOT/bin/omarchy-hw-x86" || fail "omarchy-hw-x86 returns true"
pass "omarchy-hw-x86 detects x86_64"

# -p in the shebang is what keeps exported functions and BASH_ENV out, so an
# ordinary Bash launch with a decoy -p argument is refused before it reads anything.
if /usr/bin/bash "$ROOT/bin/omarchy-hw-platform" -p >/dev/null 2>"$test_tmp/error"; then
  fail "omarchy-hw-platform refuses an ordinary Bash launch"
fi
grep -Fq "Refusing an unsafe Bash startup" "$test_tmp/error" || fail "omarchy-hw-platform explains the refusal" "$(cat "$test_tmp/error")"
pass "the detector refuses an ordinary Bash launch with a decoy -p"
