# Pacman repository templates. Every platform has a pacman.conf and mirrorlist
# for each channel it offers, copied into place whole: x86 in default/pacman.
# Sourcing this file only defines functions; it never changes the system.

# The directory holding <platform>'s pacman-<channel>.conf and
# mirrorlist-<channel>. A channel without both files isn't offered there.
omarchy_pacman_templates() {
  case ${1:-} in
    x86) echo "$OMARCHY_PATH/default/pacman" ;;
    *)
      echo "Error: Unknown platform '${1:-}'." >&2
      return 1
      ;;
  esac
}

# The channel a machine takes when none is named: stable for x86.
omarchy_pacman_default_channel() {
  case ${1:-} in
    x86) echo stable ;;
    *)
      echo "Error: Unknown platform '${1:-}'." >&2
      return 1
      ;;
  esac
}
