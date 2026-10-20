#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"
source "$ROOT/default/bash/fns/herdr"

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

mkdir -p "$test_dir/first project's files" "$test_dir/second project"
log="$test_dir/herdr.log"

herdr() {
  if [[ $1 == "workspace" ]]; then
    return
  elif [[ $1 == "tab" ]]; then
    printf '{"result":{"root_pane":{"pane_id":"new-pane"}}}\n'
  elif [[ $1 == "pane" && $2 == "run" ]]; then
    printf '%s\n' "$4" >>"$log"
  fi
}

export HERDR_PANE_ID="current-pane"
export HERDR_WORKSPACE_ID="workspace"

cd "$test_dir"
hdlm "opencode --flag='value with spaces'" "agy --model custom"

mapfile -t commands <"$log"

expected_first=$(printf 'cd %q && hdl %q %q' \
  "$test_dir/first project's files" "opencode --flag='value with spaces'" "agy --model custom")
expected_second=$(printf 'hdl %q %q' "opencode --flag='value with spaces'" "agy --model custom")

[[ ${commands[0]} == "$expected_first" ]] || fail "hdlm safely quotes its first queued command"
pass "hdlm safely quotes its first queued command"

[[ ${commands[1]} == "$expected_second" ]] || fail "hdlm preserves agent argument boundaries"
pass "hdlm preserves agent argument boundaries"

: >"$log"
hdlm "opencode --quiet"
mapfile -t commands <"$log"
expected_first=$(printf 'cd %q && hdl %q' "$test_dir/first project's files" "opencode --quiet")

[[ ${commands[0]} == "$expected_first" ]] || fail "hdlm omits an absent second agent argument"
pass "hdlm omits an absent second agent argument"
