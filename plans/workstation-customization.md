# Workstation Specification & Customization Plan: ASUS ProArt X870E & RTX 5060 Ti AI Workstation

This document defines the architecture, system configuration, repository customizations, test updates, and atomic commit strategy to produce a minimal, bloat-free operating system and ISO installation image for the target workstation.

---

## 1. System Architecture & Hardware Profile

### 1.1 Target Hardware Specification

- **Motherboard**: ASUS ProArt X870E-CREATOR WIFI (BIOS 2004)
  - Super I/O Controller: Nuvoton NCT6799D via ISA bus `0290` (kernel module `nct6775`). Actively monitors all 7 motherboard fan headers (fan1-fan7), voltages, and motherboard temperatures.
  - ASUS Embedded Controller: `asus_ec_sensors` driver reporting CPU, VRM, and chipset thermal zones.
  - USB4 / Thunderbolt 4 Controller: ASMedia ASM4242 (`thunderbolt` driver).
  - Primary NVMe Controller: Samsung SSD S4LV008/Pascal (`nvme` driver).
  - SATA Controller: AMD 600/800 Series Promontory 21 (`ahci` driver).
- **CPU**: AMD Ryzen 9 9900X (12C/24T, Zen 5 Granite Ridge, Family 19h Model 44h)
  - Microcode: `amd-ucode`
  - Core telemetry: `k10temp`
  - Frequency scaling: `amd_pstate` autonomous frequency scaling with Energy Performance Preference (EPP)
- **Memory**: 64 GB DDR5 RAM
- **Display & Desktop Graphics**: AMD Granite Ridge Radeon 610M iGPU (PCI `79:00.0`, RDNA2, `boot_vga=1`)
  - Monitor: LG UltraFine 27" 4K (3840x2160@60Hz) connected directly to the motherboard HDMI port (`card2-HDMI-A-2`)
  - Driver: `amdgpu` kernel module, Mesa Gallium/RadeonSI, Mesa RADV (`vulkan-radeon`), and Mesa VA-API (`radeonsi_drv_video.so`) on AMD VCN 4.0
- **Dedicated AI Compute Accelerator**: NVIDIA GeForce RTX 5060 Ti 16GB (Blackwell GB206, PCI `01:00.0`, subsystem ZOTAC `19da:1772`)
  - Drivers: `nvidia-open-dkms` and `nvidia-utils`
  - Compute stack: CUDA Toolkit, cuDNN, PyTorch, llama.cpp / llama-server
  - Display connections: None (headless compute only)
- **Networking**:
  - 2.5 GbE Ethernet: Intel I226-V (`igc` driver)
  - 10 GbE Ethernet: Aquantia AQC113 NBase-T (`atlantic` driver)
  - Wi-Fi 7: MediaTek MT7927 / Filogic 380 802.11be PCIe (`mt7925e` driver)
  - Bluetooth: MediaTek MT7927 Bluetooth 5.4 USB (`btusb` driver with `mt7927-bt-firmware`)
- **Audio**:
  - Realtek ALC1220 HD Audio (`snd_hda_intel`)
  - AMD Granite Ridge Audio (`snd_hda_intel`)
  - NVIDIA GB206 Audio (disabled via udev rule `99-disable-nvidia-audio.rules`)
- **Peripherals**:
  - Corsair HX1000i Digital PSU: Monitored via kernel `corsair-psu` hwmon interface (voltage, current, fan, temperature)
  - APC Smart/Back-UPS: USB HID power device monitored via `apcupsd`
  - Keychron Link & Dell Optical Mouse: Standard USB HID

---

## 2. Low-Level RTX GPU Isolation & Graphics Architecture

The NVIDIA GeForce RTX 5060 Ti functions exclusively as a dedicated AI compute accelerator. It is completely obliterated from the display, window management, and user-space graphics subsystems.

```
+-----------------------------------------------------------------------------------+
| USER-SPACE GRAPHICS & DISPLAY                                                     |
| Hyprland / Aquamarine -> Auto-binds to sole DRM node: /dev/dri/card0 (AMD iGPU)   |
| Google Chrome / MPV   -> Auto-loads Mesa radeonsi via sole AMD render node        |
| Vulkan Graphics Apps  -> Auto-loads Mesa RADV (sole ICD manifest on disk)        |
| EGL / OpenGL          -> Auto-loads Mesa (sole vendor library on disk)            |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| KERNEL DRM / KMS SUBSYSTEM                                                        |
| /dev/dri/card0, /dev/dri/renderD128 <--- amdgpu (AMD Granite Ridge Radeon 610M)   |
| (NO NVIDIA DRM NODES EXIST - nvidia_drm and nvidia_modeset BLOCKED VIA STUBS)     |
+-----------------------------------------------------------------------------------+

+-----------------------------------------------------------------------------------+
| AI COMPUTE STACK                                                                  |
| PyTorch, llama.cpp / llama-server, vLLM, TensorRT, CUDA                          |
| Direct communication via: /dev/nvidia0, /dev/nvidiactl, /dev/nvidia-uvm          |
| Kernel modules: nvidia, nvidia_uvm                                                |
+-----------------------------------------------------------------------------------+
```

### 2.1 Kernel Level: DRM Node Elimination

1. The kernel display subsystem creates `/dev/dri/card*` and `/dev/dri/renderD*` nodes exclusively when `nvidia_drm` initializes modesetting.
2. In `etc/modprobe.d/nvidia-compute-only.conf`, execution stubs block both `nvidia_drm` and `nvidia_modeset`:
   ```ini
   install nvidia_drm /bin/true
   install nvidia_modeset /bin/true
   blacklist nvidia_drm
   blacklist nvidia_modeset
   options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_PreserveVideoMemoryAllocations=1
   ```
3. In `etc/mkinitcpio.conf.d/nvidia.conf`, the initramfs includes only the modules required for early display and CUDA unified virtual memory:
   ```ini
   MODULES+=(amdgpu nvidia nvidia_uvm)
   ```
4. As a direct result, `/dev/dri/` contains only AMD GPU nodes. No display compositor or Xwayland instance can detect the NVIDIA GPU as a display adapter.

### 2.2 Filesystem & Package Level: Physical Graphics Elimination

1. **VA-API**: The `libva-nvidia-driver` package is excluded from all package sets. Mesa's `radeonsi_drv_video.so` is the sole VA-API driver on the filesystem, handling video decoding via AMD VCN 4.0.
2. **Vulkan & EGL/GLX Elimination via Physical Deletion + `NoExtract`**:
   - The files are physically deleted from the filesystem:
     - `/usr/share/vulkan/icd.d/nvidia_icd.json`
     - `/usr/share/glvnd/egl_vendor.d/10_nvidia.json`
   - To prevent `pacman -Syu` updates to `nvidia-utils` from restoring them, pacman's `NoExtract` directive is configured in `default/pacman/pacman.conf`:
     ```ini
     NoExtract = usr/share/vulkan/icd.d/*nvidia* usr/share/glvnd/egl_vendor.d/*nvidia* usr/lib/libEGL_nvidia* usr/lib/libGLESv2_nvidia* usr/lib/libGLX_nvidia*
     ```
   This ensures NVIDIA graphics files do not exist and can never be re-introduced during system life.
3. **Absence of Artificial Environment Variables**:
   Because the kernel only exposes AMD DRM nodes, and the filesystem contains only AMD graphics driver manifests:
   - `vulkan-icd-loader` automatically loads Mesa RADV (`radeon_icd.x86_64.json`).
   - `libva` automatically binds to `/dev/dri/renderD128` and selects `radeonsi`.
   - `libglvnd` automatically selects Mesa EGL/GLX.
   - Aquamarine / Hyprland automatically binds to `/dev/dri/card0`.
     No manual environment variables (`LIBVA_DRIVER_NAME`, `VK_DRIVER_FILES`, `__GLX_VENDOR_LIBRARY_NAME`, `AQ_DRM_DEVICES`) are needed.

---

## 3. Dedicated AI Stack & Infrastructure

The workstation provides a modern AI engineering stack optimized for local acceleration on the RTX 5060 Ti (16GB VRAM) and cloud orchestration across target providers: Google Gemini, Kimi K3, DeepSeek, and OpenRouter.

### 3.1 Local Inference: llama.cpp & llama-server

The system deploys upstream `llama.cpp` and `llama-server` rather than Ollama.

- **Architecture**: Native C/C++ compiled directly with CUDA targeting Blackwell architecture (`sm_120`). Zero wrapper overhead.
- **Model Storage**: Standard raw `.gguf` files stored directly on disk without proprietary blob packaging.
- **Launch Control**: Direct command-line flag control over context length (`-c`), batch size (`-b`), micro-batching (`-ub`), flash attention (`-fa`), and continuous batching slots (`-np`).
- **VRAM Optimization**: Native KV cache quantization (`-ctk q8_0`, `-ctv q8_0`) allowing a 32k context model to run entirely in 16GB VRAM with zero memory spill.
- **OpenAI-Compatible Serving**: `llama-server` provides an OpenAI-compatible HTTP endpoint (`http://localhost:8080/v1`) with native prompt caching (`--prompt-cache`).

#### Implementation: `llama-server` Systemd User Service

Managed via `~/.config/systemd/user/llama-server.service`:

```ini
[Unit]
Description=llama.cpp OpenAI-Compatible Inference Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/llama-server --host 127.0.0.1 --port 8080 -ngl 99 -fa -c 32768 --prompt-cache /var/cache/llama/prompt.bin
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
```

### 3.2 Coding Agent Harnesses: OpenCode vs. Pi vs. Aider

#### Evaluation & Orthogonality

Aider and Pi are evaluated against OpenCode:

- **Aider**: A Python-based terminal pair programming tool (`pipx install aider-chat`). While it pioneered git commit tracking and repo-maps, it brings a heavy Python dependency tree and a rigid conversation loop. OpenCode natively supports git diffs, file inspection, and LSP integration without Python bloat.
- **Pi / Oh-My-Pi**: A minimalist terminal agent CLI in TypeScript/Rust. It excels at fast stdin pipes (`git diff | pi`), but lacks an interactive TUI, multi-file diff viewer, and integrated file tree. OpenCode supports both an interactive TUI and non-interactive CLI execution (`opencode --auto "..."`), completely covering Pi's functionality.
- **Conclusion**: Pi and Aider are **not orthogonal** to OpenCode. OpenCode cleanly subsumes their capabilities while supporting all required providers (DeepSeek, Kimi K3, OpenRouter, and local `llama-server`). Adding Pi or Aider introduces redundancy.

#### Selected Agent Profile

- **Default Agent**: `antigravity-cli` (`agy`) configured as system default via `omarchy-default-agent agy` for Google Gemini models.
- **Universal Community Agent**: `opencode` retained as the single community harness for DeepSeek, Kimi K3, OpenRouter, and local `llama-server`.
- **Purged**: `claude`, `codex`, `copilot`, `cursor-agent`, `grok`, `pi`, `oh-my-pi`, `ori`, `crush`, `hermes`, `openclaw`.

### 3.3 Voice Dictation & Audio Transcription

- **`voxtype-bin`** (Real-time Inline Dictation): Push-to-talk background daemon (Right Alt / F9 / Super+Ctrl+X). Uses local Whisper models and types directly into the focused Wayland window via `wtype`. Instant, private, zero GUI footprint.
- **`whisper.cpp`** (Fast Audio File Transcription): Pure C++ Whisper engine with CUDA acceleration on the RTX 5060 Ti (`whisper-cli`) for transcribing recorded audio files, meetings, and voice memos at 50x real-time speed.
- **Purged**: `superwhisper-bin` (proprietary GUI) and `monologue` (redundant GUI recorder).

---

## 4. XDG Base Directory Compliance & Clean Home Directory

To eliminate dotfile clutter in `$HOME`, comprehensive XDG environment variables and tool-specific redirections are established in `default/bash/envs` and `default/uwsm/env.d/10-omarchy`.

### 4.1 Standard XDG Base Directories

```bash
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
```

### 4.2 Tool-Specific XDG Redirections

The following exports ensure CLI tools, compilers, and runtimes write to proper XDG locations instead of `$HOME`:

```bash
# NVIDIA / CUDA
export CUDA_CACHE_PATH="$XDG_CACHE_HOME/nv"

# Rust / Cargo
export CARGO_HOME="$XDG_DATA_HOME/cargo"
export RUSTUP_HOME="$XDG_DATA_HOME/rustup"

# Go
export GOPATH="$XDG_DATA_HOME/go"

# Node / NPM
export NODE_REPL_HISTORY="$XDG_DATA_HOME/node_repl_history"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"

# Python
export PYTHONSTARTUP="$XDG_CONFIG_HOME/python/pythonrc"
export PYTHON_HISTORY="$XDG_STATE_HOME/python/history"
export IPYTHONDIR="$XDG_CONFIG_HOME/ipython"
export JUPYTER_CONFIG_DIR="$XDG_CONFIG_HOME/jupyter"

# Docker
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"

# Shell & Utilities
export WGETRC="$XDG_CONFIG_HOME/wgetrc"
export LESSHISTFILE="$XDG_STATE_HOME/less/history"
export HISTFILE="$XDG_STATE_HOME/bash/history"
```

### 4.3 PATH Synchronization

Append the redirected tool binary directories to `$PATH`:

```bash
case ":$PATH:" in
  *":$XDG_DATA_HOME/cargo/bin:"*) ;;
  *) PATH="${PATH:+$PATH:}$XDG_DATA_HOME/cargo/bin" ;;
esac
case ":$PATH:" in
  *":$XDG_DATA_HOME/go/bin:"*) ;;
  *) PATH="${PATH:+$PATH:}$XDG_DATA_HOME/go/bin" ;;
esac
```

---

## 5. Migration Evaluation for Fresh Installation

Omarchy includes approximately 200 historical migration scripts in `migrations/*.sh`.

### 5.1 Fresh Install Migration Semantics

On a fresh installation, `bin/omarchy-provision-user` executes during first boot:

```bash
mkdir -p "$state_dir/migrations"
for migration in "$OMARCHY_PATH"/migrations/*.sh; do
  [[ -f $migration ]] && touch "$state_dir/migrations/$(basename "$migration")"
done
```

**Semantics**: Every shipped migration script is marked as complete instantly by creating empty touch markers. **Zero historical migrations run on a fresh install.** They are never executed; the ISO filesystem already contains the current baseline state.

### 5.2 Fork & Upstream Rebase Strategy

Deleting 200 migration files from the fork would trigger perpetual git conflicts during future `git rebase upstream/quattro` operations whenever upstream touches, renames, or appends migrations.

- **Decision**: All existing upstream migration files are retained untouched in `migrations/`.
- **Runtime Cost**: 0ms execution time and ~200KB disk footprint.
- **Rebase Benefit**: 100% clean, conflict-free rebasing with upstream in the `migrations/` tree.

---

## 6. Workstation Pruning & Bloat Removal

All hardware configurations, applications, and features that do not directly serve this workstation are removed from the repository.

### 6.1 Hardware Support Cleanup

- **Foreign Platform Package Files Removed**: `install/omarchy-aarch64*.packages`.
- **Non-Workstation Hardware Scripts Removed**:
  - `install/hardware/apple/` (MacBook T2, SPI keyboard, brcmfmac)
  - `install/hardware/asus/fix-*` (All laptop-specific display, touchpad, and speaker scripts)
  - `install/hardware/asus-rog.sh` (ASUS ROG laptop Armoury)
  - `install/hardware/dell-xps*` (Dell XPS 13 laptop scripts)
  - `install/hardware/framework/` & `framework16.sh` (Framework laptops)
  - `install/hardware/gb10/` (NVIDIA GB10 ARM desktops)
  - `install/hardware/intel/` (All Intel CPU/GPU/camera/thermald scripts)
  - `install/hardware/lenovo/` (Yoga and ThinkPad laptops)
  - `install/hardware/qualcomm/` (Snapdragon ARM laptops)
  - `install/hardware/surface.sh` & `fix-surface-keyboard.sh` (Microsoft Surface)
  - `install/hardware/fix-bcm43xx.sh`, `fix-elgato-camlink-4k.sh`, `fix-fkeys.sh`, `fix-n1x-gpu-memory.sh`, `n1x.sh`, `fix-synaptic-touchpad.sh`, `fix-tuxedo-backlight.sh`, `fix-yt6801-ethernet-adapter.sh`, `speaker-tuning.sh`
- **Workstation Hardware Script Added**:
  - `install/hardware/asus/proart-x870e.sh`: Loads `nct6775` (Super I/O) and `asus_ec_sensors` (EC thermal sensors) into `/etc/modules-load.d/workstation-sensors.conf`.
- **Streamlined `install/hardware/all.sh`**:
  ```bash
  run_logged "$OMARCHY_INSTALL/hardware/network.sh"
  run_logged "$OMARCHY_INSTALL/hardware/set-wireless-regdom.sh"
  run_logged "$OMARCHY_INSTALL/hardware/bluetooth.sh"
  run_logged "$OMARCHY_INSTALL/hardware/nvidia.sh"
  run_logged "$OMARCHY_INSTALL/hardware/vulkan.sh"
  run_logged "$OMARCHY_INSTALL/hardware/asus/proart-x870e.sh"
  run_logged "$OMARCHY_INSTALL/hardware/pacman.sh"
  ```

### 6.2 Gaming Removal

- **Packages Removed**: `moonlight-qt`, `lib32-nvidia-utils`, `lib32-mesa`, multilib gaming packages.
- **Scripts Removed**: `bin/omarchy-install-gaming-*`, `bin/omarchy-remove-gaming-*`, `bin/omarchy-launch-battlenet`, `bin/omarchy-games-retro-*`.
- **Window Rules Removed**: `default/hypr/apps/battlenet.lua`, `geforce.lua`, `moonlight.lua`, `retroarch.lua`, `steam.lua`.
- **Menu Definitions**: Stripped `install.gaming` and `remove.gaming` blocks from `default/omarchy/omarchy-menu.jsonc`.

### 6.3 Windows Support Removal

- **Scripts Removed**: `bin/omarchy-windows-vm`, `bin/omarchy-windows-key`, `bin/omarchy-install-service-microsoft`.
- **Packages Removed**: `dotnet-runtime`, `gvfs-smb`.
- **Menu Definitions**: Stripped `install.windows` and `remove.windows` from `default/omarchy/omarchy-menu.jsonc`.

### 6.4 Video Production & Heavy Media Removal

- **Packages Removed**: `kdenlive` (video editor), `obs-studio` (streaming studio), `omacut` (video/audio trimmer), `pinta` (image editor).
- **Window Rules Removed**: `default/hypr/apps/davinci-resolve.lua`, `default/hypr/apps/webcam-overlay.lua`.
- **Retained Screen Capture Infrastructure**:
  - Desktop capture utilities: `bin/omarchy-capture-screenshot`, `bin/omarchy-capture-screenrecording`, `bin/omarchy-capture-screenrecording-process`, `bin/omarchy-capture-region`, `bin/omarchy-capture-text`, `bin/omarchy-capture-qr`.
  - Supporting packages retained: `grim` (Wayland frame grabber), `slurp` (geometry picker), `wl-clipboard` (clipboard pipes), `tesseract` (OCR text extraction), `zbar` (QR decoder), `gpu-screen-recorder` (hardware video capture via AMD VCN), `ffmpeg` (muxing and encoding), `pipewire` (desktop and mic audio capture).

### 6.5 Language & Localization Streamlining

- **Locales Supported**: English (`en_US.UTF-8`) and Indian English (`en_IN.UTF-8`).
- **Input Method Engines Removed**:
  - `fcitx5-chewing` (Traditional Chinese)
  - `fcitx5-chinese-addons` (Simplified Chinese)
  - `fcitx5-hangul` (Korean)
  - `fcitx5-mozc` (Japanese)
  - `fcitx5-table-extra`
- **Keybindings Removed**: `default/hypr/bindings/jis.lua` (Japanese keyboard keys).
- **Translations Removed**: Non-English translation trees under `default/i18n/` pruned, retaining English (`en`), Indian English (`en_IN`), and structural definitions (`locales.json`).
- **Complete Font Retention**:
  To guarantee that viewing Indian regional languages, CJK, and global technical documentation is never blocked:
  - `noto-fonts`: Full unicode coverage (Latin, Greek, Cyrillic, etc.)
  - `noto-fonts-cjk`: Full CJK coverage
  - `noto-fonts-emoji`: Color emoji glyphs
  - Indian Language Script Fonts: Comprehensive Noto Indic packages covering Devanagari (Hindi, Marathi, Sanskrit), Tamil, Telugu, Kannada, Malayalam, Bengali, Gujarati, Gurmukhi, and Odia
  - System Fonts: `ttf-ia-writer`, `ttf-jetbrains-mono-nerd-basic`, `woff2-font-awesome`

---

## 7. Refined Applications Inventory

| Application                      | Category     | Role                               | Action                                                 |
| -------------------------------- | ------------ | ---------------------------------- | ------------------------------------------------------ |
| `google-chrome`                  | Browser      | Primary Web Browser                | **RETAIN** (Exclusive browser)                         |
| `chromium`                       | Browser      | Open-source browser                | **REMOVE**                                             |
| `foot`                           | Terminal     | Wayland terminal emulator          | **RETAIN**                                             |
| `nautilus`                       | File Manager | GNOME Files                        | **RETAIN**                                             |
| `obsidian`                       | Notes        | Markdown knowledge base            | **RETAIN**                                             |
| `libreoffice-fresh`              | Office       | Document suite                     | **RETAIN**                                             |
| `pinta`                          | Graphics     | Image editor                       | **REMOVE**                                             |
| `imv`                            | Graphics     | Lightweight image viewer           | **RETAIN**                                             |
| `mpv`                            | Media        | Video / audio player               | **RETAIN**                                             |
| `evince`                         | Documents    | PDF / Document viewer              | **RETAIN**                                             |
| `gnome-disk-utility`             | System       | Partition & disk manager           | **RETAIN**                                             |
| `localsend`                      | Network      | Local network file transfer        | **RETAIN**                                             |
| `moonlight-qt`                   | Streaming    | Game streaming client              | **REMOVE**                                             |
| `omawrite`                       | Omarchy App  | Text editor                        | **REMOVE**                                             |
| `1Password`                      | Utility      | Password manager launcher          | **REMOVE**                                             |
| `kdenlive`                       | Media        | Video editor                       | **REMOVE**                                             |
| `obs-studio`                     | Media        | Streaming / recording suite        | **REMOVE**                                             |
| `omacut`                         | Omarchy App  | Audio/video trimmer                | **REMOVE**                                             |
| `gpu-screen-recorder`            | Capture      | Screen recording backend           | **RETAIN** (Used by `omarchy-capture-screenrecording`) |
| `visual-studio-code-bin`         | Dev          | Code editor                        | **RETAIN**                                             |
| `omarchy-nvim` / `neovim`        | Dev          | Terminal code editor               | **RETAIN**                                             |
| `lazygit`                        | Dev          | Git TUI                            | **RETAIN**                                             |
| `lazydocker`                     | Dev          | Docker TUI                         | **RETAIN**                                             |
| `btop`                           | System       | Hardware & process monitor         | **RETAIN**                                             |
| `cliamp`                         | Media        | Terminal music player              | **RETAIN**                                             |
| `omacalc`                        | Omarchy App  | Floating calculator                | **RETAIN**                                             |
| `aether`                         | Omarchy App  | Application launcher               | **RETAIN**                                             |
| `hype`                           | Omarchy App  | Presentation viewer                | **RETAIN**                                             |
| `signed`                         | Omarchy App  | PDF document signer                | **RETAIN**                                             |
| `voxtype-bin`                    | AI Dictation | Real-time push-to-talk dictation   | **RETAIN**                                             |
| `whisper.cpp`                    | AI Audio     | Fast local GPU audio transcription | **ADD**                                                |
| `llama.cpp`                      | AI Compute   | Local inference engine & server    | **ADD**                                                |
| `cuda` & `cudnn`                 | AI Compute   | NVIDIA GPU compute runtime         | **ADD**                                                |
| `nvidia-container-toolkit`       | AI Compute   | Docker container GPU access        | **ADD**                                                |
| `cups` & `system-config-printer` | System       | Printing support                   | **RETAIN**                                             |
| `WhatsApp`                       | Web App      | Messaging launcher                 | **RETAIN**                                             |

---

## 8. Test Suite & Documentation Alignment

### 8.1 Automated Test Suite Updates

- **`test/cli`**:
  - Remove test cases (lines 90-106) asserting on deleted commands (`omarchy-install-gaming-xbox-cloud`, `omarchy-install-gaming-xbox-controllers`, `omarchy-install-gaming-geforce-now`, `omarchy-install-gaming-gpu-lib32`).
  - Verify `commands --check` and `commands --json` validate cleanly without missing binary summaries or broken aliases.
- **`test/shell.d/`**:
  - Retire `test/shell.d/windows-vm-compose-test.sh`, `test/shell.d/windows-vm-mount-boundary-test.sh`, and `test/shell.d/windows-vm-test.sh` to match the removal of `omarchy-windows-vm`.
- **Target Metrics**:
  - `./test/cli`: 100% passing tests.
  - `./test/shell`: 100% passing tests.

### 8.2 Documentation Updates

- Update `docs/` and `manual/` to document the workstation-specific profile, compute-only GPU model, and streamlined application landscape.

---

## 9. Atomic Commit Strategy for Upstream Rebase Friendliness

To ensure that future `git rebase upstream/quattro` operations remain seamless and conflict-free, all changes are organized into a strict sequence of 8 atomic, cohesive commits.

### Commit 1: `workstation: add ASUS ProArt X870E hardware profile and sensors`

- **Scope**: Hardware scripts and package lists.
- **Files**:
  - `[NEW] install/hardware/asus/proart-x870e.sh`
  - `[MODIFY] install/hardware/all.sh`
  - `[DELETE] install/omarchy-aarch64*.packages`
  - `[DELETE] install/hardware/apple/`, `install/hardware/asus/fix-*`, `asus-rog.sh`, `dell-xps*`, `framework*`, `gb10/`, `intel/`, `lenovo/`, `qualcomm/`, `surface.sh`, etc.

### Commit 2: `gpu: configure RTX 5060 Ti as compute-only and obliterate nvidia graphics`

- **Scope**: Modprobe, mkinitcpio, pacman, and Hyprland graphics configs.
- **Files**:
  - `[NEW] etc/modprobe.d/nvidia-compute-only.conf`
  - `[MODIFY] etc/mkinitcpio.conf.d/nvidia.conf`
  - `[MODIFY] default/pacman/pacman.conf` (adds `NoExtract`)
  - `[MODIFY] default/hypr/nvidia.lua` (clears NVIDIA display envs)
  - `[MODIFY] install/omarchy-other.packages` (drops `libva-nvidia-driver`)

### Commit 3: `purge: remove gaming, windows vm, and video production software`

- **Scope**: Gaming, Windows VM, and heavy video software removal.
- **Files**:
  - `[DELETE] bin/omarchy-*-gaming-*`, `omarchy-launch-battlenet`, `omarchy-games-retro-*`
  - `[DELETE] bin/omarchy-windows-vm`, `omarchy-windows-key`, `omarchy-install-service-microsoft`
  - `[DELETE] default/hypr/apps/battlenet.lua`, `geforce.lua`, `moonlight.lua`, `retroarch.lua`, `steam.lua`
  - `[DELETE] default/hypr/apps/davinci-resolve.lua`, `webcam-overlay.lua`
  - `[MODIFY] default/omarchy/omarchy-menu.jsonc` (prunes gaming and Windows trees)
  - `[MODIFY] install/omarchy-base.packages` (drops `kdenlive`, `obs-studio`, `omacut`, `moonlight-qt`, `lib32-nvidia-utils`, `lib32-mesa`, `dotnet-runtime`, `gvfs-smb`)

### Commit 4: `locale: streamline languages to English while retaining global fonts`

- **Scope**: Language definitions, translations, and font specifications.
- **Files**:
  - `[MODIFY] install/omarchy-base.packages` (drops CJK input engines; ensures Indic and global Noto fonts)
  - `[DELETE] default/hypr/bindings/jis.lua`
  - `[DELETE] default/i18n/<foreign-dirs>`

### Commit 5: `apps: refine desktop applications and configure google-chrome`

- **Scope**: Default desktop application set.
- **Files**:
  - `[MODIFY] install/omarchy-base.packages` (drops `chromium`, `pinta`, `omawrite`, `1Password`; keeps `google-chrome`)
  - `[MODIFY] default/hypr/bindings/applications.lua` (updates keybindings for refined apps)
  - `[MODIFY] default/omarchy/omarchy-menu.jsonc` (removes pruned app entries)

### Commit 6: `ai: configure antigravity default, opencode universal harness, and llama-server`

- **Scope**: AI harness configurations, local inference, and compute packages.
- **Files**:
  - `[MODIFY] etc/mise/conf.d/omarchy-tools.toml` (retains `antigravity-cli`, `opencode`, `kimi`, `uv`, `gh`, `hunk`; purges unneeded harnesses)
  - `[MODIFY] bin/omarchy-default-agent` (sets `agy` as default)
  - `[DELETE] bin/omarchy-agent-usage-claude`, `omarchy-agent-usage-codex`, `omarchy-agent-usage-grok`
  - `[NEW] ~/.config/systemd/user/llama-server.service`
  - `[MODIFY] install/omarchy-base.packages` / `install/omarchy-other.packages` (adds `cuda`, `cudnn`, `nvidia-container-toolkit`, `llama.cpp`, `whisper.cpp`)

### Commit 7: `env: enforce XDG directory compliance and clean home directory`

- **Scope**: Shell environment and XDG path exports.
- **Files**:
  - `[MODIFY] default/bash/envs` (exports comprehensive XDG directories and tool redirections)
  - `[MODIFY] default/uwsm/env.d/10-omarchy`

### Commit 8: `tests: align test suites and documentation with workstation changes`

- **Scope**: Automated tests and documentation.
- **Files**:
  - `[MODIFY] test/cli` (removes assertions on deleted gaming/windows commands)
  - `[DELETE] test/shell.d/windows-vm-*.sh`
  - `[MODIFY] docs/` and `manual/`
