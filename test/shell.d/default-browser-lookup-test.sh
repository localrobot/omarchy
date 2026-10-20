#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/config" "$test_tmp/data/applications" "$test_tmp/system/applications"

export HOME="$test_tmp/home"
export XDG_CONFIG_HOME="$test_tmp/config"
export XDG_CONFIG_DIRS="$test_tmp/etc"
export XDG_DATA_HOME="$test_tmp/data"
export XDG_DATA_DIRS="$test_tmp/system"
export XDG_CURRENT_DESKTOP=Hyprland
export BROWSER=omarchy-launch-browser
export OMARCHY_TEST_XDG_SETTINGS_LOG="$test_tmp/xdg-settings"

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
printf '%s\n' "${BROWSER:-unset}" >"$OMARCHY_TEST_XDG_SETTINGS_LOG"
echo fallback.desktop
SH
export PATH="$mock_bin:$ROOT/bin:$PATH"

for browser in google-chrome custom-browser; do
  printf '#!/bin/bash\n' >"$mock_bin/$browser"
done
chmod +x "$mock_bin"/*

echo "Exec=google-chrome %U" >"$XDG_DATA_HOME/applications/google-chrome.desktop"
echo "Exec=custom-browser %u" >"$XDG_DATA_DIRS/applications/custom-browser.desktop"
# An entry of Omarchy's own left behind by a browser since removed, shadowing
# a system copy that the launchers would never read.
echo "Exec=removed-browser %U" >"$XDG_DATA_HOME/applications/removed.desktop"
echo "Exec=custom-browser %U" >"$XDG_DATA_DIRS/applications/removed.desktop"

cat >"$XDG_CONFIG_HOME/mimeapps.list" <<'EOF'
[Added Associations]
x-scheme-handler/http=custom-browser.desktop;

[Default Applications]
text/html=custom-browser.desktop
x-scheme-handler/http=missing.desktop;removed.desktop;google-chrome.desktop;
EOF

[[ $(omarchy-cmd-default-browser) == "google-chrome.desktop" ]] ||
  fail "default browser is the first installed http handler in mimeapps.list"
[[ ! -e $OMARCHY_TEST_XDG_SETTINGS_LOG ]] ||
  fail "default browser skips xdg-settings when mimeapps.list names one"

cat >"$XDG_CONFIG_HOME/hyprland-mimeapps.list" <<'EOF'
[Default Applications]
x-scheme-handler/http=custom-browser.desktop
EOF

[[ $(omarchy-cmd-default-browser) == "custom-browser.desktop" ]] ||
  fail "default browser prefers the desktop-specific mimeapps.list"

rm "$XDG_CONFIG_HOME/hyprland-mimeapps.list"
printf '[Default Applications]\nx-scheme-handler/http=missing.desktop\n' >"$XDG_CONFIG_HOME/mimeapps.list"

[[ $(omarchy-cmd-default-browser) == "google-chrome.desktop" ]] ||
  fail "default browser falls back to google-chrome.desktop when no listed handler is installed"

pass "default browser reads mimeapps.list and falls back to google-chrome.desktop"
