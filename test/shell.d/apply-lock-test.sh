#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

apply_lock="$ROOT/bin/omarchy-apply-lock"

root_path_guard=$(awk '
  /^if \(\( EUID == 0 \)\); then$/ { inside = 1 }
  inside { print }
  inside && /^fi$/ { exit }
' "$apply_lock")
grep -Fx '  export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin' <<<"$root_path_guard" >/dev/null ||
  fail "the root lock helper replaces its inherited command path"
if grep -E '(\.local/bin|target_user|target_home)' <<<"$root_path_guard" >/dev/null; then
  fail "the root lock helper does not retain a user-controlled command directory"
fi
pass "the root lock helper uses only trusted command directories"

root_runner=()
root_runtime_available=1
if (( EUID != 0 )); then
  if command -v unshare >/dev/null && unshare --user --map-root-user true 2>/dev/null; then
    root_runner=(unshare --user --map-root-user)
  else
    root_runtime_available=0
  fi
fi

if (( ! root_runtime_available )); then
  skip "no unprivileged user namespace; skipping the root lock-helper runtime test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

trusted_root_bin="$test_tmp/trusted-root-bin"
password_pam="$test_tmp/omarchy-lock-password"
fingerprint_pam="$test_tmp/omarchy-lock-fingerprint"
fprintd_resume="$test_tmp/fprintd-resume"
fprintd_timeout="$test_tmp/10-stop-timeout.conf"
patched_helper="$test_tmp/omarchy-apply-lock-patched"
target_user=omarchy-regression-user

mkdir -p "$trusted_root_bin"
for helper in grep rm tee install rmdir dirname cut getent; do
  if [[ -x /usr/bin/$helper ]]; then
    ln -s "/usr/bin/$helper" "$trusted_root_bin/$helper"
  fi
done

awk \
  -v password_pam="$password_pam" \
  -v fingerprint_pam="$fingerprint_pam" \
  -v fprintd_resume="$fprintd_resume" \
  -v fprintd_timeout="$fprintd_timeout" \
  -v trusted_root_bin="$trusted_root_bin" '
  {
    line = $0
    gsub("/etc/pam\\.d/omarchy-lock-password", password_pam, line)
    gsub("/etc/pam\\.d/omarchy-lock-fingerprint", fingerprint_pam, line)
    gsub("/usr/lib/systemd/system-sleep/fprintd-resume", fprintd_resume, line)
    gsub("/etc/systemd/system/fprintd.service.d/10-stop-timeout.conf", fprintd_timeout, line)
    if (line == "  export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin") {
      print "  export PATH=\"" trusted_root_bin "\""
      next
    }
    if (line == "if omarchy-shell lock status >/dev/null 2>&1; then") {
      print "if false; then"
      next
    }
    print line
  }
' "$apply_lock" >"$patched_helper"
chmod +x "$patched_helper"

# Plant legacy files to verify cleanup
touch "$fingerprint_pam" "$fprintd_resume" "$fprintd_timeout"

if ! output=$(OMARCHY_INSTALL_USER="$target_user" "${root_runner[@]}" /bin/bash "$patched_helper" 2>&1); then
  fail "patched lock helper failed" "$output"
fi

[[ -s $password_pam ]] || fail "lock helper did not create password PAM file"
grep -F "pam_faillock.so" "$password_pam" >/dev/null || fail "password PAM configuration missing pam_faillock"
grep -F "pam_unix.so" "$password_pam" >/dev/null || fail "password PAM configuration missing pam_unix"

[[ ! -e $fingerprint_pam ]] || fail "lock helper did not remove legacy fingerprint PAM file"
[[ ! -e $fprintd_resume ]] || fail "lock helper did not remove legacy fprintd resume hook"
[[ ! -e $fprintd_timeout ]] || fail "lock helper did not remove legacy fprintd timeout configuration"

pass "the lock helper configures password authentication and removes legacy fingerprint files"
