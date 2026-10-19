# Hardware support for ASUS ProArt X870E-CREATOR WIFI desktop motherboard.
#
# Configures the Nuvoton NCT6799D Super I/O chip (nct6775 module) for fan speed,
# voltage, and thermal sensor monitoring, as well as the ASUS Embedded
# Controller sensor driver (asus_ec_sensors module).

if omarchy-hw-asus-proart-x870e; then
  sensors_conf=${OMARCHY_SENSORS_CONF:-/etc/modules-load.d/workstation-sensors.conf}
  mkdir -p "$(dirname "$sensors_conf")"

  if [[ ! -f $sensors_conf ]] || ! grep -qxF 'nct6775' "$sensors_conf" 2>/dev/null; then
    cat >"$sensors_conf" <<'EOF'
# Super I/O and EC sensor monitoring for ASUS ProArt X870E
nct6775
asus_ec_sensors
EOF
  fi

  # Load modules for the active session if not already in memory
  modprobe nct6775 2>/dev/null || true
  modprobe asus_ec_sensors 2>/dev/null || true
fi

