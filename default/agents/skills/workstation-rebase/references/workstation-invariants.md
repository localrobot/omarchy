# Workstation Invariants Reference

This document is the authoritative, unbreakable definition of the custom workstation configuration. During rebases against upstream Omarchy, these invariants take absolute precedence. If an upstream change contradicts any invariant, the upstream change must be rejected, deleted, or adapted.

## 1. Workstation Hardware Profile

The workstation is a dedicated desktop workstation:

- **Motherboard**: ASUS ProArt X870E-CREATOR WIFI
- **CPU**: AMD Ryzen 9 9900X (12 cores, 24 threads)
- **iGPU**: AMD Radeon Graphics (RDNA 2 display driving)
- **dGPU**: Headless NVIDIA GeForce RTX 5060 Ti (Blackwell compute & CUDA accelerator)
- **Platform Architecture**: Strictly `x86_64` (`x86`)

### Allowed Hardware Code

- `install/hardware/asus/proart-x870e.sh`: Loads `nct6775` (Super I/O) and `asus_ec_sensors` (Embedded Controller) kernel modules.
- `bin/omarchy-hw-asus-proart-x870e`: Hardware detector checking DMI vendor (`ASUSTeK COMPUTER INC.`) and product name (`ProArt X870E-CREATOR WIFI`).
- `bin/omarchy-hw-platform`: Returns `x86`.
- `bin/omarchy-hw-x86`: Returns 0.
- `bin/omarchy-hw-nvidia`: Headless compute detection.
- `bin/omarchy-hw-vulkan`: Vulkan device detection.
- `bin/omarchy-hw-external-monitors`: Desktop external monitor detection.
- `bin/omarchy-hw-webcam`: USB webcam detection.
- `bin/omarchy-hw-vm`: VM environment detection.
- `bin/omarchy-hw-display`: Standard x86 DRM and DDC backlight device detection (`amdgpu_bl*`, `intel_backlight`, `acpi_video*`).

### Strictly Forbidden Hardware Code (Must Delete or Prune on Sight)

- **Apple Silicon & Mac**: Any code referencing `aarch64-apple`, `omarchy-mac`, `omarchy-mac-boot`, `appletb_backlight` (Touch Bar), `gmux_backlight` / `apple-gmux` (Mac dual GPU), `asdcontrol` (Studio Display), or `/usr/lib/omarchy/mac*`.
- **Other Non-x86 Platforms**: Any code referencing Qualcomm Snapdragon (`aarch64-qualcomm`), NVIDIA Jetson / GB10 (`aarch64-gb10`), Ampere (`aarch64-n1x`), or generic ARM (`aarch64`).
- **Laptop Hardware Profiles in `install/hardware/`**:
  - `install/hardware/apple/`
  - `install/hardware/asus-rog.sh` and `install/hardware/asus/fix-*` (ASUS ROG laptops, Armoury, Anime Matrix, Asusctl)
  - `install/hardware/dell-xps*`
  - `install/hardware/framework*`
  - `install/hardware/intel/`
  - `install/hardware/lenovo/`
  - `install/hardware/qualcomm/`
  - `install/hardware/surface.sh`
- **Laptop Peripheral Quirks**:
  - Touchpad gesture configuration (`gestures` block in `default/hypr/hyprland.lua`).
  - Battery/sleep inhibitors for specific foreign laptops.
  - Keyboard backlight daemons for foreign gaming keyboards (e.g., `bin/omarchy-theme-set-keyboard-asus-rog`).

---

## 2. Terminal Invariant: Foot Sole Terminal

- **Sole Supported Terminal**: `foot` (package `foot`, desktop launcher `foot.desktop`).
- **Forbidden Terminals**: `alacritty`, `ghostty`, `kitty`, `wezterm`, `xterm`.
- **Configuration & Themes**:
  - `config/foot/foot.ini`
  - `default/themed/foot.ini.tpl`
  - `bin/omarchy-theme-set-foot` (applies palette dynamically via OSC escape codes).
- **Prohibited Code**:
  - `bin/omarchy-restart-terminal` (deleted; foot updates dynamically without restarting).
  - Any installer or setting pointing default terminal to anything other than `foot`.
  - `bin/omarchy-default-terminal` must only accept `foot`.

---

## 3. Editor Invariants: VS Code & Neovim Sole Editors

- **Sole Supported Editors**:
  - `vscode` (package `visual-studio-code-bin`, binary `code`, desktop `code.desktop`).
  - `nvim` (package `neovim`, binary `nvim`).
- **Forbidden Editors**: `zed`, `emacs`, `sublime_text` / `sublime-text-4`, `vim` / `gvim`, `helix`, `nano`.
- **Configuration & Installers**:
  - `bin/omarchy-default-editor` must only accept `code` or `nvim`.
  - `bin/omarchy-install-editor-vscode` is the sole editor installer script.
  - `bin/omarchy-theme-set-vscode`: Generates local extension theme for VS Code.
- **Prohibited Code**:
  - `bin/omarchy-install-editor-zed`, `bin/omarchy-install-editor-emacs`, or other editor installers.
  - Any menu or launcher entry offering to install non-retained editors.

---

## 4. Browser Invariant: Google Chrome Sole Browser

- **Sole Supported Browser**: `google-chrome` (package `google-chrome`, binary `google-chrome-stable`, desktop `google-chrome.desktop`).
- **Forbidden Browsers**: `chromium`, `firefox`, `brave`, `microsoft-edge`, `zen-browser`, `opera`, `vivaldi`.
- **Configuration & Policies**:
  - Managed policy directory: Strictly `/etc/opt/chrome/policies/managed/`.
  - Initial preferences: `/opt/google/chrome/initial_preferences` configured with dark mode and skipping EULA.
  - Theme template: `default/themed/chrome.theme.tpl` generating `~/.local/state/omarchy/current/theme/chrome.theme`.
  - Flag configs: `config/chrome-flags.conf` and `~/.config/chrome-flags.conf`.
- **Prohibited Code**:
  - Any references to `chromium`, `firefox`, `brave`, `edge`, or `zen` in `bin/omarchy-install-browser`, `bin/omarchy-theme-set-browser`, `bin/omarchy-theme-set-browser-policy`, or `install/helpers/browser-policy.sh`.
  - `default/firefox/` directory.
  - `config/chromium/` directory.

---

## 5. Theme Invariants: 5 Retained Themes

- **Retained Themes (Exactly 5)**:
  1. `themes/everforest`
  2. `themes/last-horizon`
  3. `themes/matte-black` (Default Seeded Theme)
  4. `themes/miasma`
  5. `themes/osaka-jade`
- **Default Seed**: Fresh installations seed `"Matte Black"` via `install/user/theme.sh`.
- **Forbidden Themes**: All other 18 themes (`catppuccin`, `nord`, `gruvbox`, `tokyo-night`, `solitude`, `retro-82`, `rose-pine`, `starship`, `white`, `lumon`, etc.).
- **Prohibited Code**:
  - Any new theme added to `themes/` outside the 5 retained ones must be deleted.
  - Any theme templates in `default/themed/` targeting purged tools (e.g. `alacritty.toml.tpl`, `kitty.conf.tpl`, `ghostty.conf.tpl`, `claude.json.tpl`) must be deleted.
  - `bin/omarchy-theme-colors-from-alacritty` must remain deleted.

---

## 6. AI Models & Agents Invariants

- **Retained AI Agents**: `agy` (Google Antigravity, default), `kimi`, `opencode`.
- **Forbidden AI Providers**: `claude`, `chatgpt`, `codex`, `grok`, `hermes`, `openclaw`, `fireworks`.
- **Prohibited Code**:
  - `bin/omarchy-theme-set-claude`, `default/themed/claude.json.tpl`.
  - SVG logos or assets for removed providers in `shell/plugins/agents/assets/` or `applications/icons/`.
  - Provider configurations in `shell/plugins/agents/manifest.json` for removed providers.
  - Shell aliases: `cx`, `cy`, `ix`, `icx`.

---

## 7. Commercial Apps & Services Invariants

- **Purged Commercial Apps**: `tailscale`, `spotify`, `slack`, `bitwarden`, `1password`, `nordvpn`, `dropbox`.
- **Prohibited Code**:
  - Application focus rules or Hyprland app rules for purged commercial apps in `default/hypr/apps/`.
  - Special volume normalization or MPRIS hacks for Spotify in `shell/plugins/panels/audio/`.
  - System reset routines scrubbing `/var/lib/tailscale` or other commercial app state.
  - Preinstalled keybindings for commercial apps in `default/hypr/bindings/applications.lua`.

---

## 8. Clean Installation & Upgrade Invariants

- **Fresh Installation Posture**: This machine runs a pristine Omarchy Quattro installation.
- **Prohibited Code**:
  - Legacy version-jumping upgrade scripts (e.g. `bin/omarchy-upgrade-to-quattro` must stay deleted).
  - Compatibility workarounds for Omarchy 3.x or pre-Quattro setups.
  - Note: Standard one-shot forward migrations in `migrations/*.sh` for existing Quattro machines are allowed only if relevant to the workstation setup.
