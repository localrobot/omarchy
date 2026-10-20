#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
agent_file="$test_home/.config/omarchy/defaults/agent"
notification_history="$test_tmp/notification-history"
agent_open_log="$test_tmp/agent-open"
launch_log="$test_tmp/launch"
inline_log="$test_tmp/inline"
mise_log="$test_tmp/mise"
mise_history="$test_tmp/mise-history"
stub_log="$test_tmp/stubs"
terminal_log="$test_tmp/terminal"
menu_log="$test_tmp/menu"
muse_login_log="$test_tmp/muse-login"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_NOTIFICATION_HISTORY"
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ $1 == ${OMARCHY_TEST_MISSING_COMMAND:-} ]]
SH

cat >"$mock_bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_LAUNCH_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_TERMINAL_LOG"
SH

cat >"$mock_bin/opencode" <<'SH'
#!/bin/bash
printf '%s\0' opencode "$@" >"$OMARCHY_TEST_AGENT_INLINE_LOG"
SH

cat >"$mock_bin/omarchy-mise-install" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_STUB_LOG"
SH

cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_MISE_LOG"
printf '%s\n' "$*" >>"$OMARCHY_TEST_MISE_HISTORY"

if [[ $1 == "where" ]]; then
  [[ ${OMARCHY_TEST_AGENT_INSTALLED:-false} == "true" ]]
  exit
fi

if [[ $1 == "ls" && -n ${OMARCHY_TEST_MISE_HAS_NPM_GROK:-} ]]; then
  printf '%s\n' "npm:@xai-official/grok  1.0.44"
  exit 0
fi

[[ ${OMARCHY_TEST_MISE_FAIL:-false} != "true" ]]
SH

cat >"$mock_bin/omarchy-menu" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_MENU_LOG"
SH

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
echo "Muse must install through mise" >&2
exit 1
SH
ln -s omarchy-pkg-add "$mock_bin/omarchy-pkg-aur-add"

cat >"$mock_bin/muse" <<'SH'
#!/bin/bash
if [[ ${1:-} == "login" ]]; then
  printf 'muse %s\n' "$*" >>"$OMARCHY_TEST_MUSE_LOGIN_LOG"
else
  printf '%s\0' muse "$@" >"$OMARCHY_TEST_AGENT_INLINE_LOG"
fi
SH

cat >"$mock_bin/omarchy-test-noop" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

for command in gum hyprctl omarchy-webapp-remove-all omarchy-tui-remove-all omarchy-pkg-drop; do
  ln -s omarchy-test-noop "$mock_bin/$command"
done

chmod +x "$mock_bin"/*

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_NOTIFICATION_HISTORY="$notification_history"
export OMARCHY_TEST_AGENT_OPEN_LOG="$agent_open_log"
export OMARCHY_TEST_AGENT_LAUNCH_LOG="$launch_log"
export OMARCHY_TEST_AGENT_INLINE_LOG="$inline_log"
export OMARCHY_TEST_MISE_LOG="$mise_log"
export OMARCHY_TEST_MISE_HISTORY="$mise_history"
export OMARCHY_TEST_STUB_LOG="$stub_log"
export OMARCHY_TEST_AGENT_TERMINAL_LOG="$terminal_log"
export OMARCHY_TEST_AGENT_MENU_LOG="$menu_log"
export OMARCHY_TEST_MUSE_LOGIN_LOG="$muse_login_log"
export OMARCHY_PATH="$ROOT"
export OMARCHY_MISE_CONFIG_PATH="$test_tmp/etc/mise/config.toml"

grok_package="grok"
legacy_grok_package="npm:@xai-official/grok"
omp_package="oh-my-pi"
legacy_omp_package="github:can1357/oh-my-pi"
crush_package="crush"
agy_package="antigravity-cli"
ori_package="ori"
legacy_ori_package="github:OpenRouterLabs/ori-releases"
kimi_package="npm:@moonshot-ai/kimi-code"
cursor_agent_package="cursor-agent"
muse_package="muse"
legacy_muse_package="http:muse[url=https://api.meta.ai/muse-launcher.sh,bin=muse,version_list_url=https://api.meta.ai/muse-code/channels/muse-stable,version_json_path=.version]"

assert_lazy_stub() {
  local package=$1
  local command=$2

  : >"$mise_history"
  "$ROOT/bin/omarchy-mise-install" "$package" "$command"
  "$test_home/.local/bin/$command" --version
  mapfile -t mise_calls <"$mise_history"

  [[ ${mise_calls[0]} == "use -g --quiet $package" && ${mise_calls[1]} == "x $package -- $command --version" ]] ||
    fail "$command lazy stub preserves its mise package"
}

assert_lazy_stub "$kimi_package" kimi
assert_lazy_stub "opencode" opencode
assert_lazy_stub "$agy_package" agy
pass "custom agent lazy stubs preserve their mise packages"

source "$ROOT/install/user/mise.sh"
lazy_config="$ROOT/etc/mise/conf.d/omarchy-tools.toml"
[[ -f $lazy_config ]] || fail "Omarchy ships the system mise config"
grep -Fx 'locked_scopes = ["project", "global"]' "$lazy_config" >/dev/null ||
  fail "system tools remain installable when the user enables locked mode"
for tool in "$agy_package" opencode; do
  grep -Eq "^$tool = \\{ version = \"latest\", lazy = true, auto_update = \"4h\", minimum_release_age = \"0s\" \\}$" "$lazy_config" ||
    fail "user setup declares $tool as a self-updating native lazy tool"
done
grep -Eq "^\"$kimi_package\" = \\{ version = \"latest\", lazy = true, auto_update = \"4h\", " "$lazy_config" ||
  fail "user setup declares $kimi_package as a self-updating native lazy tool"
[[ $(grep -c 'auto_update = "4h"' "$lazy_config") == 3 ]] || fail "only the agent CLIs update themselves"
for tool in node uv; do
  grep -Eq "^$tool = \\{ version = \"latest\", lazy = true, minimum_release_age = \"0s\" \\}$" "$lazy_config" ||
    fail "user setup declares $tool as a native lazy tool"
done
[[ $(grep -c 'lazy = true' "$lazy_config") == 9 ]] || fail "user setup declares every default mise tool as lazy"
grep -Fx "reshim --system" "$mise_history" >/dev/null || fail "user setup builds the system lazy bootstrap shims"
pass "user setup configures system lazy tools from registry shorthands"
: >"$stub_log"
source "$ROOT/install/user/mise.sh"
[[ ! -s $stub_log ]] || fail "user setup must not create handwritten mise wrappers"
pass "user setup leaves ordinary lazy wrappers to mise"

"$ROOT/bin/omarchy-mise-install" "$muse_package" muse
"$ROOT/bin/omarchy-mise-install" "$kimi_package" kimi
touch "$test_home/.local/bin/agy" "$test_home/.local/bin/ori"
omarchy-remove-preinstalls >/dev/null
for command in agy omp ori grok crush cursor-agent muse kimi; do
  [[ ! -e $test_home/.local/bin/$command ]] || fail "Remove Preinstalls deletes the $command lazy stub"
done
pass "Remove Preinstalls deletes every optional agent lazy stub"

# Cursor's installer links the same path, so anything but the mise wrapper is
# the user's own install.
touch "$test_home/.local/bin/cursor-agent.official"
ln -s cursor-agent.official "$test_home/.local/bin/cursor-agent"
omarchy-remove-preinstalls >/dev/null
[[ -L $test_home/.local/bin/cursor-agent ]] || fail "Remove Preinstalls keeps an official Cursor CLI install"
rm -f "$test_home/.local/bin/cursor-agent" "$test_home/.local/bin/cursor-agent.official"
pass "Remove Preinstalls keeps an official Cursor CLI install"
printf '#!/bin/bash\necho user-muse\n' >"$test_home/.local/bin/muse"
chmod +x "$test_home/.local/bin/muse"
omarchy-remove-preinstalls >/dev/null
[[ $("$test_home/.local/bin/muse") == "user-muse" ]] || fail "Remove Preinstalls deletes a user-managed Muse"
rm "$test_home/.local/bin/muse"
pass "Remove Preinstalls keeps a user-managed Muse install"


[[ $(omarchy-default-agent) == "agy" ]] || fail "default agent defaults to agy"
pass "default agent defaults to agy"

source "$ROOT/default/bash/aliases"
[[ $(alias a) == "alias a='omarchy-agent --inline'" ]] ||
  fail "terminal alias launches the default agent inline"
pass "terminal alias launches the default agent inline"

grep -Fq 'o.bind("SUPER + SHIFT + CTRL + A", "Agent", "omarchy-agent --pick")' \
  "$ROOT/default/hypr/bindings/utilities.lua" ||
  fail "agent launcher has a keyboard shortcut"
pass "agent launcher has a keyboard shortcut"

cat >"$mock_bin/omarchy-agent" <<'SH'
#!/bin/bash
printf '%s\0' omarchy-agent "$@" >"$OMARCHY_TEST_AGENT_OPEN_LOG"
SH
chmod +x "$mock_bin/omarchy-agent"
hash -r

declare -A expected_agents=(
  [opencode]="opencode"
  [open-code]="opencode"
  [agy]="agy"
  [antigravity]="agy"
  [antigravity-cli]="agy"
  [gemini]="agy"
  [gemini-cli]="agy"
  [kimi]="kimi"
  [kimi-code]="kimi"
)

declare -A expected_packages=(
  [opencode]="opencode"
  [agy]="$agy_package"
  [kimi]="$kimi_package"
)

for selection in "${!expected_agents[@]}"; do
  expected=${expected_agents[$selection]}
  : >"$agent_open_log"
  : >"$stub_log"
  OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent "$selection"
  [[ $(omarchy-default-agent) == $expected ]] || fail "default agent canonicalizes $selection"

  mapfile -d '' -t mise_args <"$mise_log"
  [[ ${mise_args[0]} == "use" && ${mise_args[1]} == "-g" ]] ||
    fail "default agent installs $selection globally through mise"
  case ${mise_args[2]} in
    "${expected_packages[$expected]}") ;;
    *) fail "default agent preserves $selection backend options" ;;
  esac

  mapfile -d '' -t agent_open_args <"$agent_open_log"
  [[ ${#agent_open_args[@]} == 1 && ${agent_open_args[0]} == "omarchy-agent" ]] ||
    fail "default agent opens $selection after selecting it"
done
pass "default agent selects and opens every supported provider and alias"
[[ -f $agent_file && ! -e $test_home/.local/state/omarchy/defaults/agent ]] ||
  fail "default agent stores its selection in Omarchy user config"
pass "default agent stores its selection in Omarchy user config"

OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent agy
: >"$notification_history"
: >"$agent_open_log"
: >"$terminal_log"
omarchy-default-agent kimi-code
mapfile -d '' -t terminal_args <"$terminal_log"
[[ ${terminal_args[0]} == "omarchy-default-agent" && ${terminal_args[1]} == "--install" && ${terminal_args[2]} == "kimi" ]] ||
  fail "missing agent installation opens in a terminal"
[[ ! -s $notification_history ]] || fail "missing agent installation skips notifications"
[[ ! -s $agent_open_log ]] || fail "missing agent installation waits to open the agent"
[[ $(omarchy-default-agent) == "agy" ]] || fail "missing agent installation waits to change the selection"

omarchy-default-agent --install kimi-code >"$test_tmp/install-output"
mapfile -d '' -t mise_args <"$mise_log"
[[ ${mise_args[0]} == "use" && ${mise_args[1]} == "-g" && ${mise_args[2]} == "$kimi_package" ]] ||
  fail "visible agent installation activates the provider globally through mise"
[[ $(omarchy-default-agent) == "kimi" ]] || fail "visible agent installation changes the selection after mise succeeds"
[[ ! -s $notification_history ]] || fail "visible agent installation leaves progress to the terminal"
[[ $(<"$test_tmp/install-output") == $'\033[2J\033[3J\033[H' ]] ||
  fail "visible agent installation clears its terminal before opening the agent"
mapfile -d '' -t agent_open_args <"$agent_open_log"
[[ ${#agent_open_args[@]} == 2 && ${agent_open_args[0]} == "omarchy-agent" && ${agent_open_args[1]} == "--inline" ]] ||
  fail "newly installed agent opens in the installation terminal"
pass "missing agents install visibly and open in the same terminal"

: >"$notification_history"
: >"$agent_open_log"
: >"$terminal_log"
OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent kimi-code
[[ ! -s $terminal_log ]] || fail "installed agent selection skips the terminal"
[[ ! -s $notification_history ]] || fail "installed agent selection skips notifications"
mapfile -d '' -t mise_args <"$mise_log"
[[ ${mise_args[0]} == "use" && ${mise_args[1]} == "-g" && ${mise_args[2]} == "$kimi_package" ]] ||
  fail "default agent still activates an installed provider globally through mise"
mapfile -d '' -t agent_open_args <"$agent_open_log"
[[ ${#agent_open_args[@]} == 1 && ${agent_open_args[0]} == "omarchy-agent" ]] ||
  fail "installed agent opens in a new terminal after selection"
pass "installed agents select and open without notifications"

# A user-managed install links ~/.local/bin, and the mise shims precede
# ~/.local/bin, so a mise copy would shadow the user's own install.
touch "$test_home/.local/bin/opencode.official"
chmod +x "$test_home/.local/bin/opencode.official"
ln -s opencode.official "$test_home/.local/bin/opencode"
: >"$terminal_log"
: >"$mise_log"
: >"$agent_open_log"
omarchy-default-agent opencode
[[ ! -s $terminal_log ]] || fail "an official OpenCode install needs no install terminal"
[[ ! -s $mise_log ]] || fail "an official OpenCode install is left to itself by mise"
[[ $(<"$agent_file") == "opencode" ]] || fail "an official OpenCode install becomes the default"
mapfile -d '' -t agent_open_args <"$agent_open_log"
[[ ${#agent_open_args[@]} == 1 && ${agent_open_args[0]} == "omarchy-agent" ]] ||
  fail "an official OpenCode install opens after selection"
rm -f "$test_home/.local/bin/opencode" "$test_home/.local/bin/opencode.official"
printf '%s\n' agy >"$agent_file"
pass "selecting an official Cursor CLI install skips mise"

# A file nothing can run is not an install; the wrapper is still wanted.
touch "$test_home/.local/bin/opencode"
: >"$terminal_log"
omarchy-default-agent opencode
mapfile -d '' -t terminal_args <"$terminal_log"
[[ ${terminal_args[*]} == "omarchy-default-agent --install opencode" ]] ||
  fail "a dead file at the wrapper's path still installs OpenCode"
rm -f "$test_home/.local/bin/opencode"
pass "a dead file at the wrapper's path does not pass for an install"

: >"$agent_open_log"
if omarchy-default-agent unsupported >"$test_tmp/invalid-output" 2>&1; then
  fail "default agent rejects unsupported providers"
fi
grep -F "Usage: omarchy-default-agent" "$test_tmp/invalid-output" >/dev/null ||
  fail "default agent explains supported providers"
[[ $(omarchy-default-agent) == "agy" ]] || fail "invalid selection preserves the current default agent"
[[ ! -s $agent_open_log ]] || fail "invalid selection does not open an agent"
pass "default agent rejects unsupported providers without changing the selection"

: >"$notification_history"
: >"$agent_open_log"
if OMARCHY_TEST_MISE_FAIL=true omarchy-default-agent --install kimi >"$test_tmp/install-failure-output" 2>&1; then
  fail "default agent rejects a failed mise installation"
fi
[[ $(omarchy-default-agent) == "agy" ]] || fail "failed installation preserves the current default agent"
grep -F "Could not install Kimi with mise" "$test_tmp/install-failure-output" >/dev/null ||
  fail "default agent reports a failed mise installation in the terminal"
[[ ! -s $notification_history ]] || fail "failed visible agent installation skips notifications"
[[ ! -s $agent_open_log ]] || fail "failed installation does not open an agent"
pass "default agent opens only after mise installs the provider"

: >"$notification_history"
: >"$agent_open_log"
if OMARCHY_TEST_AGENT_INSTALLED=true OMARCHY_TEST_MISE_FAIL=true omarchy-default-agent kimi >"$test_tmp/setup-failure-output" 2>&1; then
  fail "default agent rejects a failed mise activation"
fi
[[ $(omarchy-default-agent) == "agy" ]] || fail "failed activation preserves the current default agent"
grep -F "Could not set Kimi as the default coding agent" "$test_tmp/setup-failure-output" >/dev/null ||
  fail "default agent reports a failed activation for an installed provider"
[[ ! -s $notification_history ]] || fail "failed activation skips notifications"
[[ ! -s $agent_open_log ]] || fail "failed activation does not open an agent"
pass "default agent reports mise failures without notifications"

# OpenCode follows the shared mise installation and launch path.
: >"$notification_history"
: >"$agent_open_log"
: >"$terminal_log"
omarchy-default-agent opencode
mapfile -d '' -t terminal_args <"$terminal_log"
[[ ${terminal_args[0]} == "omarchy-default-agent" && ${terminal_args[1]} == "--install" && ${terminal_args[2]} == "opencode" ]] ||
  fail "missing OpenCode installation opens in a terminal"
[[ ! -s $notification_history ]] || fail "missing OpenCode installation skips notifications"
[[ ! -s $agent_open_log ]] || fail "missing OpenCode installation waits to open the agent"
[[ $(omarchy-default-agent) == "agy" ]] || fail "missing OpenCode installation waits to change the selection"

if OMARCHY_TEST_MISE_FAIL=true omarchy-default-agent --install opencode >"$test_tmp/opencode-install-failure-output" 2>&1; then
  fail "missing OpenCode rejects a failed mise installation"
fi
[[ $(omarchy-default-agent) == "agy" ]] || fail "failed OpenCode installation preserves the current default"
[[ ! -s $agent_open_log ]] || fail "failed OpenCode installation skips launch"
grep -F "Could not install OpenCode with mise" "$test_tmp/opencode-install-failure-output" >/dev/null ||
  fail "failed OpenCode installation identifies mise"
pass "failed OpenCode mise installation preserves the selection"

# Without Omarchy's declarations nothing declares OpenCode, so selecting it adds it
# to the user's config.
: >"$mise_history"
omarchy-default-agent --install opencode >/dev/null
grep -Fx "use -g opencode" "$mise_history" >/dev/null ||
  fail "OpenCode selection adds OpenCode to the user config when no system config declares it"
rm -f "$agent_file"

# mise skips the declarations for a user who removed the preinstalls, so the
# same applies.
mkdir -p "$(dirname "$OMARCHY_MISE_CONFIG_PATH")" "$test_home/.config/mise"
cp "$ROOT/etc/mise/conf.d/omarchy-tools.toml" "$OMARCHY_MISE_CONFIG_PATH"
printf 'ignored_config_paths = ["%s"]\n' "$OMARCHY_MISE_CONFIG_PATH" >"$test_home/.config/mise/miserc.toml"
: >"$mise_history"
omarchy-default-agent --install opencode >/dev/null
grep -Fx "use -g opencode" "$mise_history" >/dev/null ||
  fail "OpenCode selection adds OpenCode to the user config after Remove Preinstalls"
rm -f "$agent_file" "$test_home/.config/mise/miserc.toml"

# With Omarchy's system config, installing is enough; the user config stays alone.
: >"$mise_history"
: >"$stub_log"
omarchy-default-agent --install opencode >"$test_tmp/opencode-install-output"
grep -Fx "install opencode" "$mise_history" >/dev/null || fail "visible OpenCode installation uses the registry shorthand"
grep -q '^use ' "$mise_history" && fail "OpenCode selection leaves the user config alone when the system config declares it"
[[ ! -s $stub_log ]] || fail "OpenCode selection recreates its preinstalled wrapper"
[[ $(omarchy-default-agent) == "opencode" ]] || fail "visible OpenCode installation changes the selection"
mapfile -d '' -t agent_open_args <"$agent_open_log"
[[ ${#agent_open_args[@]} == 2 && ${agent_open_args[0]} == "omarchy-agent" && ${agent_open_args[1]} == "--inline" ]] ||
  fail "newly installed OpenCode opens in the installation terminal"
pass "OpenCode installs visibly through mise and opens directly"

: >"$terminal_log"
: >"$agent_open_log"
OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent open-code
[[ ! -s $terminal_log ]] || fail "installed OpenCode selection skips the terminal"
[[ $(omarchy-default-agent) == "opencode" ]] || fail "default agent canonicalizes open-code"
mapfile -d '' -t agent_open_args <"$agent_open_log"
[[ ${#agent_open_args[@]} == 1 && ${agent_open_args[0]} == "omarchy-agent" ]] ||
  fail "installed OpenCode opens in a new terminal after selection"
pass "installed OpenCode selects and opens directly"

OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent agy
: >"$agent_open_log"
if OMARCHY_TEST_AGENT_INSTALLED=true OMARCHY_TEST_MISE_FAIL=true omarchy-default-agent open-code >"$test_tmp/opencode-failure-output" 2>&1; then
  fail "default agent rejects a failed OpenCode activation"
fi
[[ $(omarchy-default-agent) == "agy" ]] || fail "failed OpenCode activation preserves the current default agent"
grep -F "Could not set OpenCode as the default coding agent" "$test_tmp/opencode-failure-output" >/dev/null ||
  fail "default agent reports a failed OpenCode activation"
[[ ! -s $agent_open_log ]] || fail "failed OpenCode activation does not open an agent"
pass "default agent reports OpenCode mise failures without changing the selection"

# A manually installed launcher belongs to the user; selecting it must not
# install a second copy or replace it with the Omarchy wrapper.
printf '#!/bin/bash\necho user-opencode\n' >"$test_home/.local/bin/opencode"
chmod +x "$test_home/.local/bin/opencode"
: >"$mise_history"
: >"$stub_log"
: >"$terminal_log"
omarchy-default-agent opencode
[[ $(omarchy-default-agent) == "opencode" ]] || fail "a user-installed OpenCode can be selected"
[[ ! -s $mise_history && ! -s $stub_log && ! -s $terminal_log ]] || fail "a user-installed OpenCode skips installation and wrapper creation"
[[ $("$test_home/.local/bin/opencode") == "user-opencode" ]] || fail "a user-installed OpenCode is preserved"
rm "$test_home/.local/bin/opencode"
pass "selecting a user-installed OpenCode preserves its launcher"

rm "$mock_bin/omarchy-agent"
hash -r

assert_launched() {
  local agent=$1
  local description=$2
  shift 2
  # Every agent window launches under the same app-id, whichever agent is
  # default, so window rules and themes see one class for all of them.
  local expected=(--app-id=org.omarchy.agent "$@")

  mapfile -d '' -t actual <"$launch_log"

  (( ${#actual[@]} == ${#expected[@]} )) ||
    fail "$agent launch $description" "expected: ${expected[*]}\nactual: ${actual[*]}"

  for ((index = 0; index < ${#expected[@]}; index++)); do
    case ${actual[$index]} in
    "${expected[$index]}") ;;
    *) fail "$agent launch $description" "expected: ${expected[*]}\nactual: ${actual[*]}" ;;
    esac
  done
}

assert_launch() {
  local agent=$1
  shift

  printf '%s\n' "$agent" >"$agent_file"
  omarchy-agent-prompt "Review this" project
  assert_launched "$agent" "forwards the interactive prompt" "$@"
}

assert_bypass() {
  local agent=$1
  shift

  printf '%s\n' "$agent" >"$agent_file"
  omarchy-agent
  assert_launched "$agent" "skips permission prompts" "$@"
}

assert_launch opencode opencode --auto --prompt "Review this project"
assert_launch agy agy --dangerously-skip-permissions --prompt-interactive "Review this project"
assert_launch kimi kimi --prompt "Review this project"
pass "agent launcher adapts initial prompts for every supported agent"

assert_bypass opencode opencode --auto
assert_bypass agy agy --dangerously-skip-permissions
assert_bypass kimi kimi --yolo
pass "agent launcher skips permission prompts for every supported agent"

printf '%s\n' "opencode" >"$agent_file"
omarchy-agent
mapfile -d '' -t launch_args <"$launch_log"
[[ ${launch_args[*]} == "--app-id=org.omarchy.agent opencode --auto" ]] ||
  fail "agent launcher starts the selected agent without an initial prompt"
pass "agent launcher starts the selected agent without an initial prompt"

omarchy-agent-prompt --inline "Review this project"
mapfile -d '' -t inline_args <"$inline_log"
[[ ${inline_args[*]} == "opencode --auto --prompt Review this project" ]] ||
  fail "inline agent launcher runs in the current terminal"
pass "inline agent launcher runs in the current terminal"

# The prompt route exists so the router can tell a prompt from a subcommand, so
# cover the public routes and not only the binaries behind them.
: >"$launch_log"
omarchy agent
mapfile -d '' -t launch_args <"$launch_log"
[[ ${launch_args[*]} == "--app-id=org.omarchy.agent opencode --auto" ]] ||
  fail "omarchy agent routes to the launcher"

# With an agent chosen there is nothing to pick, so the keybinding launches.
: >"$launch_log"
: >"$menu_log"
omarchy-agent --pick
mapfile -d '' -t launch_args <"$launch_log"
[[ ${launch_args[*]} == "--app-id=org.omarchy.agent opencode --auto" ]] ||
  fail "--pick launches once an agent is chosen"
[[ ! -s $menu_log ]] || fail "--pick opens no menu once an agent is chosen"
pass "--pick launches once an agent is chosen"

: >"$launch_log"
omarchy agent prompt "Review this project"
mapfile -d '' -t launch_args <"$launch_log"
[[ ${launch_args[*]} == "--app-id=org.omarchy.agent opencode --auto --prompt Review this project" ]] ||
  fail "omarchy agent prompt routes the prompt to the launcher"

: >"$launch_log"
if omarchy agent Review this project >"$test_tmp/positional-output" 2>&1; then
  fail "omarchy agent rejects a positional prompt"
fi
grep -F "omarchy agent prompt" "$test_tmp/positional-output" >/dev/null ||
  fail "omarchy agent points a positional prompt at the prompt route"
[[ ! -s $launch_log ]] || fail "omarchy agent starts nothing for a positional prompt"
pass "omarchy agent keeps prompts on the prompt route"

printf '%s\n' "missing" >"$agent_file"
if OMARCHY_TEST_MISSING_COMMAND=missing omarchy-agent >"$test_tmp/missing-output" 2>&1; then
  fail "agent launcher rejects a missing default command"
fi
grep -F "missing is not installed" "$test_tmp/missing-output" >/dev/null ||
  fail "agent launcher explains when the default command is missing"
pass "agent launcher reports a missing default command"


