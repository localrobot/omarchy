#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Test driver package selection for RTX 5060 Ti compute
actual=$(bash -euo pipefail -c '
  lspci() { printf "%s\n" "3D controller: NVIDIA Corporation [GeForce RTX 5060 Ti]"; }
  omarchy-pkg-add() {
    printf "%s\n" "$*"
    exit 0
  }
  source "$ROOT/install/hardware/nvidia.sh"
')
expected='nvidia-open-dkms nvidia-utils'
[[ $actual == "$expected" ]] || fail "RTX 5060 Ti installs open dkms and utils" "expected: $expected; actual: $actual"
pass "RTX 5060 Ti installs nvidia-open-dkms and nvidia-utils"

# Test that full script writes compute-only modprobe and mkinitcpio configurations
tmp_test=$(mktemp -d)
trap 'rm -rf "$tmp_test"' EXIT

TEST_ROOT="$tmp_test" bash -euo pipefail -c '
  mkdir -p "$TEST_ROOT/etc/modprobe.d" "$TEST_ROOT/etc/mkinitcpio.conf.d"
  lspci() { printf "%s\n" "3D controller: NVIDIA Corporation [GeForce RTX 5060 Ti]"; }
  omarchy-pkg-add() { :; }

  # Seduce script to write to our test root instead of real /etc
  sed "s|/etc/|$TEST_ROOT/etc/|g" "$ROOT/install/hardware/nvidia.sh" >"$TEST_ROOT/run-nvidia.sh"
  source "$TEST_ROOT/run-nvidia.sh"
'

[[ -f "$tmp_test/etc/modprobe.d/nvidia.conf" ]] || fail "nvidia.conf modprobe file created"
grep -q "install nvidia_drm /bin/true" "$tmp_test/etc/modprobe.d/nvidia.conf" || fail "nvidia_drm is stubbed with /bin/true"
grep -q "install nvidia_modeset /bin/true" "$tmp_test/etc/modprobe.d/nvidia.conf" || fail "nvidia_modeset is stubbed with /bin/true"
grep -q "NVreg_OpenRmEnableUnsupportedGpus=1" "$tmp_test/etc/modprobe.d/nvidia.conf" || fail "OpenRm option is set"
pass "modprobe config stubs display/modesetting modules and sets OpenRm"

[[ -f "$tmp_test/etc/mkinitcpio.conf.d/nvidia.conf" ]] || fail "nvidia.conf mkinitcpio file created"
grep -q "MODULES+=(amdgpu nvidia nvidia_uvm)" "$tmp_test/etc/mkinitcpio.conf.d/nvidia.conf" || fail "mkinitcpio early loads amdgpu and nvidia compute"
pass "mkinitcpio config early-loads amdgpu and compute-only nvidia modules"
