#!/bin/bash

# Audit tool for workstation rebase: enforces workstation invariants and identifies foreign additions

set -euo pipefail

OMARCHY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../../.." && pwd)
cd "$OMARCHY_ROOT"

mode="${1:-post}"
errors=0
warnings=0

log_pass() {
  echo -e "\e[32m✔ [PASS]\e[0m $1"
}

log_fail() {
  echo -e "\e[31m✘ [FAIL]\e[0m $1"
  ((errors++))
}

log_warn() {
  echo -e "\e[33m▲ [WARN]\e[0m $1"
  ((warnings++))
}

log_info() {
  echo -e "\e[34mℹ [INFO]\e[0m $1"
}

echo "=========================================================="
echo " Omarchy Workstation Invariant Audit (Mode: $mode)"
echo " Target: ASUS ProArt X870E + AMD Ryzen 9 9900X + RTX 5060 Ti"
echo "=========================================================="

# 1. Audit themes
echo ""
echo "--- Checking Themes (Exactly 5 Retained) ---"
retained_themes=("everforest" "last-horizon" "matte-black" "miasma" "osaka-jade")
for theme_path in themes/*; do
  [[ -d $theme_path ]] || continue
  theme_name=$(basename "$theme_path")
  is_retained=0
  for retained in "${retained_themes[@]}"; do
    if [[ $theme_name == "$retained" ]]; then
      is_retained=1
      break
    fi
  done
  if ((is_retained)); then
    log_pass "Theme retained: $theme_name"
  else
    log_fail "Foreign/non-retained theme detected: $theme_path (MUST BE DELETED)"
  fi
done

# 2. Audit hardware profiles in install/hardware/
echo ""
echo "--- Checking Hardware Profiles (Workstation & Generic Only) ---"
allowed_hw_items=(
  "install/hardware/all.sh"
  "install/hardware/network.sh"
  "install/hardware/set-wireless-regdom.sh"
  "install/hardware/bluetooth.sh"
  "install/hardware/nvidia.sh"
  "install/hardware/vulkan.sh"
  "install/hardware/asus"
)

for hw_item in install/hardware/*; do
  [[ -e $hw_item ]] || continue
  is_allowed=0
  for allowed in "${allowed_hw_items[@]}"; do
    if [[ $hw_item == "$allowed" ]]; then
      is_allowed=1
      break
    fi
  done

  if ((is_allowed)); then
    if [[ $hw_item == "install/hardware/asus" ]]; then
      for sub_item in install/hardware/asus/*; do
        if [[ $sub_item == "install/hardware/asus/proart-x870e.sh" ]]; then
          log_pass "Workstation motherboard profile: $sub_item"
        else
          log_fail "Foreign ASUS laptop script detected: $sub_item (MUST BE DELETED)"
        fi
      done
    else
      log_pass "Workstation hardware script: $hw_item"
    fi
  else
    log_fail "Foreign hardware profile detected: $hw_item (MUST BE DELETED)"
  fi
done

# 3. Audit forbidden files that must never exist
echo ""
echo "--- Checking for Forbidden Purged Files ---"
forbidden_files=(
  "bin/omarchy-restart-terminal"
  "bin/omarchy-theme-colors-from-alacritty"
  "bin/omarchy-upgrade-to-quattro"
  "bin/omarchy-theme-set-claude"
  "bin/omarchy-install-editor-emacs"
  "bin/omarchy-install-editor-zed"
  "default/themed/claude.json.tpl"
  "default/themed/chromium.theme.tpl"
  "default/themed/alacritty.toml.tpl"
  "default/themed/kitty.conf.tpl"
  "default/themed/ghostty.conf.tpl"
  "default/firefox"
  "config/chromium"
  "config/alacritty"
  "config/kitty"
  "config/ghostty"
  "applications/icons/ChatGPT.png"
  "default/fonts/omarchy/hermes.svg"
  "default/hypr/apps/bitwarden.lua"
  "default/hypr/apps/hermes.lua"
  "default/hypr/apps/webcam-overlay.lua"
  "test/shell.d/upgrade-to-quattro-test.sh"
)

for forbidden in "${forbidden_files[@]}"; do
  if [[ -e $forbidden ]]; then
    log_fail "Forbidden purged file exists: $forbidden (MUST BE DELETED)"
  else
    log_pass "Verified absent: $forbidden"
  fi
done

# 4. Audit foreign patterns in runtime code (bin/ and default/)
echo ""
echo "--- Scanning for Banned Code Patterns in bin/ and default/ ---"
scan_patterns=(
  "appletb_backlight:Apple Touch Bar reference"
  "gmux_backlight:Apple gmux reference"
  "omarchy-restart-terminal:Purged terminal restart script call"
  "omarchy-theme-colors-from-alacritty:Purged alacritty theme converter"
  "omarchy-upgrade-to-quattro:Purged upgrade script reference"
  "omarchy-theme-set-claude:Purged Claude theme hook"
  "archlinuxarm-keyring:Arch Linux ARM keyring reference"
)

for entry in "${scan_patterns[@]}"; do
  pattern="${entry%%:*}"
  description="${entry##*:}"
  matches=$(git grep -n "$pattern" bin/ default/ 2>/dev/null || true)
  if [[ -n $matches ]]; then
    log_fail "Found banned pattern in runtime code ($description):"
    echo "$matches" | head -n 5
  else
    log_pass "Clean of pattern: $pattern"
  fi
done

# 5. Check broken symlinks
echo ""
echo "--- Checking Symlink Integrity ---"
broken_links=$(find . -xtype l 2>/dev/null || true)
if [[ -n $broken_links ]]; then
  log_fail "Broken symlinks found:"
  echo "$broken_links"
else
  log_pass "Zero broken symlinks"
fi

# 6. Check command metadata
echo ""
echo "--- Checking Command Metadata ---"
if bin/omarchy commands --check >/dev/null 2>&1; then
  log_pass "bin/omarchy commands --check passed"
else
  log_fail "bin/omarchy commands --check failed"
fi

echo ""
echo "=========================================================="
if ((errors > 0)); then
  echo -e "\e[31m✘ AUDIT FAILED with $errors error(s) and $warnings warning(s).\e[0m"
  echo "Action required: Delete or fix the flagged files before proceeding."
  exit 1
else
  echo -e "\e[32m✔ AUDIT PASSED! All workstation invariants are intact.\e[0m"
  exit 0
fi
