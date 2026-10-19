#!/bin/bash

source "$(dirname "$0")/base-test.sh"

export PATH="$ROOT/bin:$PATH"

test_tmp=$(mktemp -d) || fail "test temp directory is available"
trap 'rm -rf "$test_tmp"' EXIT

dmi_dir="$test_tmp/sys/class/dmi/id"
mkdir -p "$dmi_dir"

# Mock DMI board_name
echo "ProArt X870E-CREATOR WIFI" > "$dmi_dir/board_name"

# Test omarchy-hw-match with board_name override
output=$(OMARCHY_DMI_DIR="$dmi_dir" "$ROOT/bin/omarchy-hw-match" "ProArt X870E")
(( $? == 0 )) || fail "omarchy-hw-match matches board_name"
pass "omarchy-hw-match matches board_name"

# Test omarchy-hw-asus-proart-x870e detector
OMARCHY_DMI_DIR="$dmi_dir" "$ROOT/bin/omarchy-hw-asus-proart-x870e"
(( $? == 0 )) || fail "omarchy-hw-asus-proart-x870e detects ProArt X870E"
pass "omarchy-hw-asus-proart-x870e detects ProArt X870E"

# Test negative match
echo "ROG STRIX B650-A GAMING" > "$dmi_dir/board_name"
echo "Other Model" > "$dmi_dir/product_name"
if OMARCHY_DMI_DIR="$dmi_dir" "$ROOT/bin/omarchy-hw-asus-proart-x870e"; then
  fail "omarchy-hw-asus-proart-x870e should fail on non-ProArt hardware"
fi
pass "omarchy-hw-asus-proart-x870e rejects unrelated hardware"

# Test install/hardware/asus/proart-x870e.sh creates modules-load config
echo "ProArt X870E-CREATOR WIFI" > "$dmi_dir/board_name"
sensors_conf="$test_tmp/etc/modules-load.d/workstation-sensors.conf"
OMARCHY_DMI_DIR="$dmi_dir" OMARCHY_SENSORS_CONF="$sensors_conf" bash "$ROOT/install/hardware/asus/proart-x870e.sh"

[[ -f "$sensors_conf" ]] || fail "workstation-sensors.conf created"
grep -qxF "nct6775" "$sensors_conf" || fail "nct6775 included in sensors config"
grep -qxF "asus_ec_sensors" "$sensors_conf" || fail "asus_ec_sensors included in sensors config"
pass "proart-x870e.sh configures Super I/O and EC sensor modules"
