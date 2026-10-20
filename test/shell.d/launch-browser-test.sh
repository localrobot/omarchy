#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"
export XDG_CONFIG_HOME="$test_home/.config" XDG_DATA_HOME="$test_home/.local/share"

cat >"$mock_bin/google-chrome-stable" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/systemd-run" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_BROWSER_LAUNCH"
SH
cat >"$mock_bin/omarchy-hyprland-focus-app" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$OMARCHY_TEST_BROWSER_FOCUS"
SH
cat >"$mock_bin/omarchy-cmd-browser-handoff" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch"
focus_log="$test_tmp/focus"
HOME="$test_home" PATH="$mock_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  bash "$ROOT/bin/omarchy-launch-browser"

[[ ! -e $focus_log ]] || fail "browser launcher leaves a new window on the current workspace"

HOME="$test_home" PATH="$mock_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  bash "$ROOT/bin/omarchy-launch-browser" --private

[[ ! -e $focus_log ]] || fail "private browser launcher leaves a new window on the current workspace"

HOME="$test_home" PATH="$mock_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
  bash "$ROOT/bin/omarchy-launch-browser" "https://example.test/authorize"

grep -F 'https://example.test/authorize' "$launch_log" >/dev/null || fail "browser launcher passes through the URL"
grep -Fx '^google-chrome.*$' "$focus_log" >/dev/null || fail "browser launcher focuses the default browser window"
pass "browser launcher follows opened links to the browser workspace"

rm -f "$launch_log"
cat >"$mock_bin/omarchy-cmd-browser-handoff" <<'SH'
#!/bin/bash
[[ $1 == "google-chrome-stable" && $2 == "https://example.test/running" ]]
SH
chmod +x "$mock_bin/omarchy-cmd-browser-handoff"

HOME="$test_home" PATH="$mock_bin:$PATH" OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" \
  OMARCHY_TEST_BROWSER_FOCUS="$focus_log" bash "$ROOT/bin/omarchy-launch-browser" "https://example.test/running"

[[ ! -e $launch_log ]] || fail "browser launcher starts no browser when the running one takes the URL"
pass "browser launcher hands a URL to the running browser"

rm -f "$mock_bin/omarchy-cmd-browser-handoff" "$launch_log"
cat >"$mock_bin/omarchy-cmd-browser-handoff" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/omarchy-cmd-browser-handoff"

launch() {
  HOME="$test_home" PATH="$mock_bin:$PATH" OMARCHY_TEST_BROWSER_LAUNCH="$launch_log" \
    OMARCHY_TEST_BROWSER_FOCUS="$focus_log" \
    bash "$ROOT/bin/omarchy-launch-browser" "$@"
}

launch "https://example.test/a--private-b"
grep -F 'https://example.test/a--private-b' "$launch_log" >/dev/null || fail "an ordinary launch leaves its arguments alone"
pass "an ordinary launch leaves its arguments alone"

launch --private
grep -F -- 'google-chrome-stable --incognito' "$launch_log" >/dev/null || fail "a private launch passes the browser's private flag"
pass "a private launch passes the browser's private flag"
