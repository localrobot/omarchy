#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

conf="$ROOT/etc/sysctl.d/90-omarchy-arp.conf"

# The kernel takes the higher of conf/all and conf/<interface>, so "all" has to
# carry the values for interfaces that exist at boot, and "default" for the
# ones a dock or Wi-Fi adapter brings later.
for key in all default; do
  grep -Fxq "net.ipv4.conf.$key.arp_ignore=1" "$conf" && pass "$key interfaces answer ARP only for their own address" || fail "$key interfaces answer ARP only for their own address"
  grep -Fxq "net.ipv4.conf.$key.arp_announce=2" "$conf" && pass "$key interfaces announce their own address" || fail "$key interfaces announce their own address"
done
[[ -z $(grep -Ev '^(#|$|net\.ipv4\.conf\.(all|default)\.arp_(ignore|announce)=[0-9]$)' "$conf") ]] && pass "the file only sets the ARP keys" || fail "the file only sets the ARP keys"
if [[ -e /proc/sys/net/ipv4/conf/all/arp_ignore ]]; then
  [[ -e /proc/sys/net/ipv4/conf/all/arp_announce && -e /proc/sys/net/ipv4/conf/default/arp_ignore ]] && pass "the keys exist on this kernel" || fail "the keys exist on this kernel"
fi
