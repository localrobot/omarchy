#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Browser and Steam installs, and Steam's removal, call the platform's own
# hooks through the real dispatcher: a Mac fixture with omarchy-mac's
# entrypoints, and x86.

require_platform_fixtures "app-install hooks on platform fixtures"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fake_platform "$tmp/apple" aarch64-apple
fake_platform "$tmp/x86" x86

# The hooks record what they were called with and which flags files the
# browser install had written by then.
lifecycle=$tmp/lifecycle
mkdir -p "$lifecycle/usr/lib/omarchy/mac"
for operation in post-install pre-remove; do
  cat >"$lifecycle/usr/lib/omarchy/mac/$operation" <<SH
#!/bin/bash
printf '%s %s\n' "$operation" "\$*" >>"$tmp/calls"
ls "\$HOME/.config" 2>/dev/null | grep -- '-flags.conf$' >"$tmp/flags-at-hook" || true
[[ ! -e $tmp/fail ]]
SH
  chmod 755 "$lifecycle/usr/lib/omarchy/mac/$operation"
done
chmod -R go-w "$lifecycle"

stub_bin=$tmp/bin
omarchy_path=$tmp/omarchy
mkdir -p "$stub_bin" "$omarchy_path/install/helpers" "$omarchy_path/config"
printf 'browser_policy_setup_dir() { :; }\nbrowser_policy_setup_firefox_distribution() { :; }\nas_root() { "$@"; }\n' \
  >"$omarchy_path/install/helpers/browser-policy.sh"
cp "$ROOT/config/chrome-flags.conf" "$omarchy_path/config/"
for command in omarchy-pkg-add omarchy-pkg-aur-add omarchy-pkg-drop; do
  printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "$*" >>"%s"\n' "$command" "$tmp/calls" >"$stub_bin/$command"
done
for command in omarchy-install-chrome-copy-url omarchy-install-chrome-ytdlp omarchy-theme-set-browser setsid; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$command"
done
chmod +x "$stub_bin"/*

run() {
  local platform=$1
  shift
  rm -f "$tmp/calls" "$tmp/flags-at-hook"
  rm -rf "$tmp/home"
  mkdir -p "$tmp/home"
  HOME="$tmp/home" OMARCHY_PATH="$omarchy_path" OMARCHY_OPT_PATH="$tmp/opt" \
    OMARCHY_PROC_ROOT="$tmp/$platform/proc" OMARCHY_LIFECYCLE_ROOT="$lifecycle" \
    PATH="$stub_bin:$tmp/$platform/bin:$ROOT/bin:$PATH" bash "$@" >"$tmp/output" 2>&1
}

# ── browsers ─────────────────────────────────────────────────────────────────

declare -A flags=(
  [chrome]=chrome-flags.conf
)
for browser in chrome; do
  run apple "$ROOT/bin/omarchy-install-browser" "$browser" || fail "apple: $browser installs" "$(cat "$tmp/output")"
  [[ $(grep -c '^post-install ' "$tmp/calls") == 1 ]] && grep -qx "post-install $browser" "$tmp/calls" ||
    fail "apple: a $browser install runs post-install $browser once" "$(cat "$tmp/calls")"
  [[ $(cat "$tmp/flags-at-hook") == "${flags[$browser]}" ]] ||
    fail "apple: the $browser hook runs once its flags file is written" "$(cat "$tmp/flags-at-hook")"
  [[ $(grep -n . "$tmp/calls" | grep -m1 'post-install' | cut -d: -f1) -gt 1 ]] ||
    fail "apple: the $browser hook runs after its package step" "$(cat "$tmp/calls")"
done
pass "apple: chrome browser install runs post-install chrome after its package and flags"

touch "$tmp/fail"
for browser in chrome; do
  if run apple "$ROOT/bin/omarchy-install-browser" "$browser"; then
    fail "apple: a failed $browser hook fails the install"
  fi
  ! grep -q 'browser installed' "$tmp/output" || fail "apple: a failed $browser hook is not announced as installed" "$(cat "$tmp/output")"
done
pass "apple: a failed browser hook fails the install"

for browser in chrome; do
  run x86 "$ROOT/bin/omarchy-install-browser" "$browser" || fail "x86: $browser installs" "$(cat "$tmp/output")"
  ! grep -q '^post-install' "$tmp/calls" || fail "x86: a $browser install runs no hook" "$(cat "$tmp/calls")"
done
rm -f "$tmp/fail"
pass "x86: browser installs run no hook, even with Mac entrypoints on disk"
