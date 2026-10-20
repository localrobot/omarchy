#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'drop:%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-pkg-drop"

# omarchy-remove-ai-claude quits the running app before deleting its state;
# a real pkill here would take the developer's own Claude with it.
cat >"$tmp_dir/bin/pkill" <<'SCRIPT'
#!/bin/bash
printf 'pkill:%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/pkill"

# omarchy-remove-ai-openclaw asks through gum whether the user's data goes
# too. The stub answers "no" unless a test says otherwise and logs the call: a
# real gum would hang the run, and one that answered "yes" on its own would be
# the data loss the default-no exists to prevent. It logs to its own file
# because the OpenClaw section below greps TEST_LOG to prove gum was never
# reached, and the pty runs here call it on purpose.
cat >"$tmp_dir/bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$TEST_GUM_LOG"
exit "${TEST_GUM_STATUS:-1}"
SCRIPT
chmod +x "$tmp_dir/bin/gum"

export TEST_GUM_LOG="$tmp_dir/gum-log"
touch "$TEST_GUM_LOG"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"

fresh_home() {
  rm -rf "$tmp_dir/home"
  mkdir -p "$tmp_dir/home"
  export HOME="$tmp_dir/home"
}

# The Codex CLI ships in its own package and resolves its runtime out of
# ~/.cache/codex-runtimes, so removing the desktop app must not take it.
fresh_home
mkdir -p "$HOME/.config/Codex" "$HOME/.cache/Codex" "$HOME/.cache/codex-runtimes/codex-primary-runtime" "$HOME/.codex"
"$ROOT/bin/omarchy-remove-ai-chatgpt" >/dev/null

[[ ! -e $HOME/.config/Codex ]] || fail "ChatGPT removal deletes the desktop app's config"
pass "ChatGPT removal deletes the desktop app's config"

[[ -d $HOME/.cache/codex-runtimes/codex-primary-runtime ]] || fail "ChatGPT removal keeps the Codex CLI's runtime cache"
pass "ChatGPT removal keeps the Codex CLI's runtime cache"

[[ -d $HOME/.codex ]] || fail "ChatGPT removal keeps the Codex CLI's config"
pass "ChatGPT removal keeps the Codex CLI's config"

# The Claude Code CLI ships in its own package and keeps its state in
# ~/.claude, ~/.claude.json, and ~/.cache/claude-cli-nodejs, so removing the
# desktop app must not take it.
fresh_home
mkdir -p "$HOME/.config/Claude" "$HOME/.cache/Claude" "$HOME/.cache/claude-cli-nodejs" "$HOME/.claude"
touch "$HOME/.claude.json"
"$ROOT/bin/omarchy-remove-ai-claude" >/dev/null

for gone in .config/Claude .cache/Claude; do
  [[ ! -e $HOME/$gone ]] || fail "Claude removal deletes the desktop app's config and caches" "$gone"
done
pass "Claude removal deletes the desktop app's config and caches"

for kept in .claude .claude.json .cache/claude-cli-nodejs; do
  [[ -e $HOME/$kept ]] || fail "Claude removal keeps the Claude Code CLI's state" "$kept"
done
pass "Claude removal keeps the Claude Code CLI's state"

grep -qx 'pkill:-x claude-desktop' "$TEST_LOG" || fail "Claude removal quits the running app before deleting its state"
pass "Claude removal quits the running app before deleting its state"

# ~/.grok belongs to the Grok CLI that omarchy-default-agent installs.
fresh_home
mkdir -p "$HOME/.config/Grok Bot" "$HOME/.grokbot" "$HOME/.grok"
"$ROOT/bin/omarchy-remove-ai-grok-bot" >/dev/null

[[ ! -e $HOME/.grokbot ]] || fail "Grok Bot removal deletes its own data"
pass "Grok Bot removal deletes its own data"

[[ -d $HOME/.grok ]] || fail "Grok Bot removal keeps the Grok CLI's state"
pass "Grok Bot removal keeps the Grok CLI's state"

# OpenClaw's gateway unit and web app launcher are the app's own; the agent
# state in ~/.openclaw is the user's. systemctl and openclaw are stubbed so the
# sandbox never reaches the real user manager or a real gateway.
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"

# Default openclaw stub: the packaged CLI predates `gateway uninstall`, so the
# remover has to fall back to its manual systemd path.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
exit 1
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"

fresh_openclaw_home() {
  fresh_home
  mkdir -p "$HOME/.config/systemd/user/default.target.wants" "$HOME/.openclaw" \
    "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps" \
    "$HOME/.local/state/omarchy/openclaw-stopped"
  touch "$HOME/.config/systemd/user/openclaw-gateway.service" \
    "$HOME/.config/systemd/user/openclaw-gateway.service.bak" \
    "$HOME/.config/systemd/user/openclaw-gateway.service.reconcile-0f1e.bak" \
    "$HOME/.config/systemd/user/openclaw-gateway.service.reconcile-0f1e.receipt.bak" \
    "$HOME/.config/systemd/user/openclaw-node.service" \
    "$HOME/.openclaw/openclaw.json" \
    "$HOME/.local/share/applications/OpenClaw.desktop" \
    "$HOME/.local/share/icons/hicolor/256x256/apps/openclaw.png" \
    "$HOME/.local/state/omarchy/openclaw-stopped/gateway"
  ln -s ../openclaw-gateway.service \
    "$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service"
  ln -s ../openclaw-node.service \
    "$HOME/.config/systemd/user/default.target.wants/openclaw-node.service"
}

# gum would ask about ~/.openclaw; the tests never run on a terminal, so it
# must not even be reached. Logging it proves that.
cat >"$tmp_dir/bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$TEST_LOG"
exit "${TEST_GUM_STATUS:-1}"
SCRIPT
chmod +x "$tmp_dir/bin/gum"

fresh_openclaw_home
"$ROOT/bin/omarchy-remove-ai-openclaw" </dev/null >/dev/null

for gone in .config/systemd/user/openclaw-gateway.service \
  .config/systemd/user/openclaw-gateway.service.bak \
  .config/systemd/user/openclaw-gateway.service.reconcile-0f1e.bak \
  .config/systemd/user/openclaw-gateway.service.reconcile-0f1e.receipt.bak \
  .config/systemd/user/default.target.wants/openclaw-gateway.service \
  .config/systemd/user/openclaw-node.service \
  .config/systemd/user/default.target.wants/openclaw-node.service \
  .local/share/applications/OpenClaw.desktop \
  .local/share/icons/hicolor/256x256/apps/openclaw.png \
  .local/state/omarchy/openclaw-stopped; do
  [[ ! -e $HOME/$gone && ! -L $HOME/$gone ]] || fail "OpenClaw removal deletes the service and launcher it installed" "$gone"
done
pass "OpenClaw removal deletes the service and launcher it installed"

grep -q '^systemctl:--user disable --now openclaw-gateway.service$' "$TEST_LOG" ||
  fail "OpenClaw removal stops the gateway service"
grep -q '^systemctl:--user disable --now openclaw-node.service$' "$TEST_LOG" ||
  fail "OpenClaw removal stops the gateway service" "node host service left running"
for unit in openclaw-gateway.service openclaw-node.service; do
  grep -q "^systemctl:--user reset-failed $unit\$" "$TEST_LOG" ||
    fail "OpenClaw removal stops the gateway service" "$unit left in systemd's failed list"
done
pass "OpenClaw removal stops the gateway service"

# Without a terminal there is nobody to ask, so the state stays and gum is
# never invoked (a gum that answered "yes" on its own would be a data loss).
[[ -f $HOME/.openclaw/openclaw.json ]] || fail "OpenClaw removal keeps the user's agent state"
! grep -q '^gum:' "$TEST_LOG" ||
  fail "OpenClaw removal keeps the user's agent state" "asked about ~/.openclaw without a terminal"
pass "OpenClaw removal keeps the user's agent state"

# The command on PATH goes; the OpenClaw it pointed at stays with the state,
# since only that copy is sure to open it. A link somewhere else is not Omarchy's.
fresh_openclaw_home
mkdir -p "$HOME/.openclaw/bin" "$HOME/.openclaw/tools/node-v24.19.0/lib" "$HOME/.local/bin"
printf '#!/usr/bin/env bash\n' >"$HOME/.openclaw/bin/openclaw"
ln -s "$HOME/.openclaw/bin/openclaw" "$HOME/.local/bin/openclaw"
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null
[[ ! -e $HOME/.local/bin/openclaw && ! -L $HOME/.local/bin/openclaw ]] || fail "OpenClaw removal takes openclaw off PATH"
[[ -f $HOME/.openclaw/bin/openclaw && -d $HOME/.openclaw/tools && -f $HOME/.openclaw/openclaw.json ]] ||
  fail "OpenClaw removal keeps the OpenClaw that can open the state"

fresh_openclaw_home
mkdir -p "$HOME/.local/bin"
ln -s /opt/openclaw/openclaw "$HOME/.local/bin/openclaw"
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null
[[ -L $HOME/.local/bin/openclaw ]] || fail "OpenClaw removal takes openclaw off PATH" "someone else's link went with it"
pass "OpenClaw removal takes openclaw off PATH and keeps the copy that can open the state"

# A CLI that knows `gateway uninstall` owns the teardown; the manual systemd
# fallback must not run.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
rm -f "$HOME/.config/systemd/user/openclaw-$1.service" \
  "$HOME/.config/systemd/user/default.target.wants/openclaw-$1.service"
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"

: >"$TEST_LOG"
fresh_openclaw_home
"$ROOT/bin/omarchy-remove-ai-openclaw" </dev/null >/dev/null

grep -q '^openclaw:gateway uninstall$' "$TEST_LOG" ||
  fail "OpenClaw removal prefers upstream's own gateway teardown"
grep -q '^openclaw:node uninstall$' "$TEST_LOG" ||
  fail "OpenClaw removal prefers upstream's own gateway teardown" "node host not handed to upstream"
! grep -q '^systemctl:--user disable' "$TEST_LOG" ||
  fail "OpenClaw removal prefers upstream's own gateway teardown" "manual disable ran too"
pass "OpenClaw removal prefers upstream's own gateway teardown"

# Without the unit file there is nothing of ours registered, so systemd stays untouched.
systemctl_calls_before=$(grep -c '^systemctl:' "$TEST_LOG" || true)
fresh_home
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null
systemctl_calls_after=$(grep -c '^systemctl:' "$TEST_LOG" || true)

[[ $systemctl_calls_before == "$systemctl_calls_after" ]] ||
  fail "OpenClaw removal leaves systemd alone when onboarding never ran"
pass "OpenClaw removal leaves systemd alone when onboarding never ran"

# A gateway that will not stop aborts the removal before the package drop:
# pacman would otherwise strand the live process on deleted code.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
exit 1
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
[[ $2 == disable ]] && exit 1
[[ $2 == is-active ]] && exit 0
exit 0
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"

drop_calls_before=$(grep -c '^drop:openclaw$' "$TEST_LOG" || true)
fresh_openclaw_home
rc=0
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null 2>&1 || rc=$?
drop_calls_after=$(grep -c '^drop:openclaw$' "$TEST_LOG" || true)

[[ $rc != 0 ]] || fail "OpenClaw removal aborts when the gateway cannot be stopped"
[[ -f $HOME/.config/systemd/user/openclaw-gateway.service ]] ||
  fail "OpenClaw removal aborts when the gateway cannot be stopped" "unit file deleted"
[[ $drop_calls_before == "$drop_calls_after" ]] ||
  fail "OpenClaw removal aborts when the gateway cannot be stopped" "package dropped anyway"
pass "OpenClaw removal aborts when the gateway cannot be stopped"

# An unreachable user manager is not a stopped gateway: every probe failing
# with no answer must still abort, not read as "confirmed inactive".
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
echo "Failed to connect to user scope bus" >&2
exit 1
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"

: >"$TEST_LOG"
fresh_openclaw_home
rc=0
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null 2>&1 || rc=$?

[[ $rc != 0 ]] || fail "OpenClaw removal aborts when systemd cannot be reached"
[[ -f $HOME/.config/systemd/user/openclaw-gateway.service ]] ||
  fail "OpenClaw removal aborts when systemd cannot be reached" "unit file deleted"
! grep -q '^drop:openclaw$' "$TEST_LOG" ||
  fail "OpenClaw removal aborts when systemd cannot be reached" "package dropped anyway"
pass "OpenClaw removal aborts when systemd cannot be reached"

# A removal that fails after taking a service down still drops that service's
# restart record, so nothing later tries to start a unit that is gone.
fresh_openclaw_home
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"
mv "$tmp_dir/bin/omarchy-pkg-drop" "$tmp_dir/omarchy-pkg-drop.real"
printf '#!/bin/bash\nexit 1\n' >"$tmp_dir/bin/omarchy-pkg-drop"
chmod +x "$tmp_dir/bin/omarchy-pkg-drop"
if "$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null 2>&1; then
  fail "OpenClaw removal fails when the package cannot be dropped"
fi
[[ ! -e $HOME/.local/state/omarchy/openclaw-stopped/gateway ]] ||
  fail "OpenClaw removal drops a service's restart record with the service, before anything else can fail"
mv "$tmp_dir/omarchy-pkg-drop.real" "$tmp_dir/bin/omarchy-pkg-drop"
pass "OpenClaw removal drops a service's restart record with the service, before anything else can fail"
