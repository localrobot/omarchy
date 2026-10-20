#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
monitors_json="$tmpdir/monitors.json"
mkdir -p "$stub_dir"

make_stub() {
  local name=$1
  local body=$2
  printf '#!/bin/bash\n%s\n' "$body" >"$stub_dir/$name"
  chmod +x "$stub_dir/$name"
}

make_stub omarchy-notification-send ':'
make_stub hyprctl 'case "$1" in
  monitors) cat "$MONITORS_JSON" ;;
  eval) printf "%s\n" "$2" >>"$EVAL_LOG" ;;
esac'

eval_log="$tmpdir/eval.log"

run_monitor() {
  local command=$1
  shift
  : >"$eval_log"
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    MONITORS_JSON="$monitors_json" \
    EVAL_LOG="$eval_log" \
    PATH="$stub_dir:$ROOT/bin:$PATH" \
    "$ROOT/bin/$command" "$@"
}

# The scaling command eval's the focused-monitor name into a Lua string.
printf '[{"name":"DP-1","focused":true,"scale":1.0,"width":1920,"height":1080,"refreshRate":60.0}]\n' \
  >"$monitors_json"
run_monitor omarchy-hyprland-monitor-scaling 1.6
grep -F 'hl.monitor({ output = "DP-1"' "$eval_log" >/dev/null ||
  fail "scaling eval's the focused connector name"
pass "scaling accepts a plain connector name"

printf '[{"name":"DP-1\\" })os.execute(\\"calc\\")--","focused":true,"scale":1.0,"width":1920,"height":1080,"refreshRate":60.0}]\n' \
  >"$monitors_json"
set +e
run_monitor omarchy-hyprland-monitor-scaling 1.6 >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "scaling rejects a focused monitor name with Lua metacharacters"
[[ ! -s $eval_log ]] || fail "an unsafe focused monitor name is not eval'd as Lua"
pass "scaling refuses an unsafe focused monitor name"
