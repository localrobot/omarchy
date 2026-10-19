#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
export OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH"

# Exit statuses: description | nvidia | vendor:device:class
while IFS='|' read -r description nvidia devices; do
  rm -rf "$tmp_dir/devices"
  mkdir -p "$tmp_dir/devices"
  slot=0
  for spec in $devices; do
    IFS=: read -r vendor device class <<<"$spec"
    device_dir="$tmp_dir/devices/$slot"
    mkdir -p "$device_dir"
    printf '%s\n' "$vendor" >"$device_dir/vendor"
    printf '%s\n' "$device" >"$device_dir/device"
    printf '%s\n' "$class" >"$device_dir/class"
    slot=$((slot + 1))
  done

  status=0
  omarchy-hw-nvidia || status=$?
  [[ $status == "$nvidia" ]] || fail "$description: nvidia" "expected $nvidia, got $status"
  pass "$description"
done <<'CASES'
AMD only|1|0x1002:0x15e7:0x030000
NVIDIA audio only|1|0x10de:0x228e:0x040300
No PCI devices|1|
Kepler (non-3D class)|1|0x10de:0x1004:0x040300
ASUS ProArt X870E Workstation (AMD iGPU + NVIDIA RTX 5060 Ti Blackwell)|0|0x1002:0x15bf:0x030000 0x10de:0x2d00:0x030000
Standalone NVIDIA GPU|0|0x10de:0x1f91:0x030000
CASES
