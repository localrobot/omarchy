# Conflict Resolution & Clean-Merge Guide

This guide provides explicit rules for handling conflicts and clean-merging commits during `git rebase upstream/quattro`.

## Principles of Workstation Resolution

1. **Invariants Outrank Upstream**: When upstream modifies code in a way that restores foreign hardware, restores deleted applications, or breaks workstation-specific consolidation, the workstation rule ALWAYS wins.
2. **Never Re-introduce Deleted Files**: If git pauses on a file that was deleted in the cleanup, do NOT resurrect it with `git checkout --ours` or `git checkout --theirs`. Remove it with `git rm <file>`.
3. **Audit Non-Conflicting Additions**: A successful git replay without conflicts does NOT mean the rebase is finished. Upstream additions of new hardware profiles, new themes, new editors, or new AI models will merge cleanly without conflicts. They must be audited and actively deleted.
4. **When Ambiguous, Stop and Ask**: If an upstream commit introduces a major new subsystem or an ambiguous utility that might be beneficial to the workstation but introduces new dependencies, stop and ask the user.

---

## Detailed Conflict Resolution Scenarios

### Scenario A: Upstream Touched a File That Was Deleted

- **Examples**:
  - Upstream changed `bin/omarchy-upgrade-to-quattro`.
  - Upstream changed `bin/omarchy-restart-terminal` or `bin/omarchy-theme-colors-from-alacritty`.
  - Upstream added or updated a file in `themes/catppuccin/` or `themes/nord/`.
  - Upstream updated `default/firefox/policies.json` or `config/chromium/Preferences`.
  - Upstream updated `bin/omarchy-theme-set-claude` or `default/themed/claude.json.tpl`.
  - Upstream updated `install/hardware/asus/fix-touchpad.sh` or `install/hardware/apple/t2.sh`.
- **Action**:
  ```bash
  git rm -f <path-to-deleted-file>
  ```
  Do not allow git to restore deleted files. Keep the deletion intact.

### Scenario B: Conflicts in Router & Metadata (`bin/omarchy`)

- Upstream might add new command categories or modify `GROUP_DESCRIPTIONS`.
- **Action**:
  - Keep upstream's core router fixes and performance improvements.
  - Reject entries for purged command categories if any were added.
  - Verify that `bin/omarchy commands --check` passes after resolution.

### Scenario C: Conflicts in Theme System (`bin/omarchy-theme-set`, `install/user/theme.sh`)

- Upstream might re-add deleted themes to default selection or add new visible retint hooks.
- **Action**:
  - Keep `matte-black` as the default seeded theme.
  - Ensure `visible_theme_commands` does not re-introduce `omarchy-restart-terminal`.
  - Ensure `other_theme_commands` does not re-introduce `omarchy-theme-set-claude`.
  - Ensure theme lists only reference the 5 retained themes.

### Scenario D: Conflicts in Browser Logic (`bin/omarchy-install-browser`, `bin/omarchy-theme-set-browser`)

- Upstream might add checks or loops for other browsers.
- **Action**:
  - Retain Google Chrome as the sole browser.
  - Policy directory must remain strictly `/etc/opt/chrome/policies/managed/`.
  - Theme template must remain `chrome.theme`.

### Scenario E: Conflicts in Terminal or Editor Defaults (`bin/omarchy-default-*`)

- Upstream might re-introduce Kitty, Ghostty, Alacritty, Zed, Emacs, or Sublime Text.
- **Action**:
  - `omarchy-default-terminal` must strictly select and validate `foot`.
  - `omarchy-default-editor` must strictly select and validate `code` or `nvim`.

### Scenario F: Conflicts in Hardware Detection (`bin/omarchy-hw-display`, `bin/omarchy-update-keyring`)

- Upstream might re-introduce Apple Touch Bar (`appletb_backlight`), Apple gmux (`gmux_backlight`), or Arch Linux ARM keyring routines (`alarm_key`).
- **Action**:
  - Discard Apple Silicon and ARM keyring routines.
  - Keep standard x86 DRM and DDC display detection and x86 pacman keyring routines.

---

## The Post-Rebase Clean-Merge Audit

Once `git rebase` completes (all commits replayed), you MUST execute the active deletion phase.

1. **Find all newly added files from upstream**:
   Compare the merge base against `upstream/quattro`:
   ```bash
   git diff --name-status $(git merge-base HEAD upstream/quattro)..HEAD
   ```
   Or inspect newly introduced files in `upstream/quattro`:
   ```bash
   git log --name-status -n 20 upstream/quattro
   ```
2. **Apply Active Deletion Rules**:
   - Check `themes/`: Any theme directory that is not `everforest`, `last-horizon`, `matte-black`, `miasma`, or `osaka-jade` must be deleted:
     ```bash
     for theme_dir in themes/*; do
       case "${theme_dir##*/}" in
         everforest|last-horizon|matte-black|miasma|osaka-jade) ;;
         *) rm -rf "$theme_dir"; git rm -rf "$theme_dir" ;;
       esac
     done
     ```
   - Check `install/hardware/`: Any script or directory other than `install/hardware/asus/proart-x870e.sh` and `install/hardware/all.sh` must be deleted.
   - Check `default/themed/`: Delete any template for non-retained tools (`alacritty.toml.tpl`, `ghostty.conf.tpl`, `kitty.conf.tpl`, `claude.json.tpl`, `chromium.theme.tpl`).
   - Check `shell/plugins/agents/assets/`: Delete any newly introduced logos for non-retained AI providers.
3. **Run Audit Script**:
   Execute `default/agents/skills/workstation-rebase/scripts/audit-upstream.sh post`.
