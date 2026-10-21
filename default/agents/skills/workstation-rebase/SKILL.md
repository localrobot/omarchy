---
name: workstation-rebase
description: >-
  REQUIRED when synchronizing, rebasing, or pulling upstream Omarchy changes into the local
  quattro or origin/quattro branch. Enforces unbreakable workstation invariants (ASUS ProArt X870E + AMD Ryzen 9 9900X + Headless RTX 5060 Ti, Foot terminal, Chrome browser, VS Code and Neovim editors, 5 retained themes, no foreign hardware or laptop code, no non-retained AI agents or commercial apps). Automatically audits incoming diffs, actively deletes newly added foreign hardware, tools, or bloat that merged cleanly without conflict, resolves merge conflicts in favor of workstation rules, validates tests, and prompts the user when ambiguous.
---

# Workstation Rebase Skill

Safely synchronize the local `quattro` branch with `upstream/quattro` while preserving and strictly enforcing all custom workstation invariants.

This skill is governed by an unbreakable mandate: **Rebasing is NOT just replaying commits and resolving conflicts.** Upstream changes that merge cleanly without a git conflict can introduce foreign hardware support, non-retained applications, or bloat. This skill actively audits and deletes any such additions.

## Topic Guides & References

Read the companion references next to this file for exhaustive details:

- [`references/workstation-invariants.md`](references/workstation-invariants.md) - Authoritative definition of allowed vs forbidden hardware, tools, and configurations.
- [`references/conflict-resolution-guide.md`](references/conflict-resolution-guide.md) - Exact resolution strategies for git conflict states and clean-merge audits.
- [`references/purged-software-matrix.md`](references/purged-software-matrix.md) - Quick lookup table of purged tools, forbidden paths, and retained equivalents.

---

## The Workstation Invariants (Summary)

Every rebase must leave the repository compliant with these 8 invariants:

1. **Hardware Profile**: Strictly ASUS ProArt X870E desktop + AMD Ryzen 9 9900X + Headless NVIDIA RTX 5060 Ti AI Accelerator on `x86_64`.
   - **Delete**: Any newly introduced hardware scripts in `install/hardware/` (e.g. Apple, ROG laptops, Dell, Framework, Lenovo, Qualcomm, Surface).
   - **Delete**: Any Apple Silicon, Touch Bar (`appletb_backlight`), Mac dual-GPU (`gmux_backlight`), or ARM keyring code.
2. **Terminal**: `foot` is the sole terminal.
   - **Delete**: Any restored or new terminal emulators (Alacritty, Ghostty, Kitty, WezTerm) or terminal restarter scripts.
3. **Editors**: `vscode` and `nvim` are the sole editors.
   - **Delete**: Any restored or new editor installers (Zed, Emacs, Sublime, Vim, Helix).
4. **Browser**: `google-chrome` is the sole browser with 100% feature parity.
   - **Delete**: Any restored or new browser configurations, themes, or policies for Chromium, Firefox, Brave, Edge, or Zen.
5. **Themes**: Exactly 5 retained themes (`everforest`, `last-horizon`, `matte-black` [default], `miasma`, `osaka-jade`).
   - **Delete**: Any newly added or restored themes in `themes/`.
6. **AI Models & Agents**: Retained agents are `agy` (default), `kimi`, and `opencode`.
   - **Delete**: Any new or restored third-party AI providers/models (Claude, ChatGPT, Grok, Hermes, Fireworks, OpenClaw).
7. **Commercial Software**: Zero commercial software hooks.
   - **Delete**: Any hooks, focus rules, or integrations for Tailscale, Spotify, Slack, Bitwarden, 1Password, NordVPN, Dropbox.
8. **Fresh Installation Posture**: Zero legacy upgrade or multi-version migration scripts.
   - **Delete**: Any `bin/omarchy-upgrade-to-*` or legacy migration wrappers.

---

## Rebase Execution Protocol

Follow these 5 distinct phases in sequence. Never skip a phase.

### Phase 1: Pre-Rebase Preparation & Upstream Inspection

1. **Verify Clean Working Tree**:
   Ensure `git status` shows nothing to commit.
2. **Fetch Upstream**:
   ```bash
   git fetch upstream quattro
   ```
3. **Inspect Incoming Changes**:
   Review incoming commits and files added upstream:
   ```bash
   git log --oneline HEAD..upstream/quattro
   git diff --name-status HEAD...upstream/quattro | grep '^A' || true
   ```
   Take note of any newly introduced files in `install/hardware/`, `themes/`, `default/themed/`, `config/`, or `bin/`.

### Phase 2: Interactive Rebase & Conflict Resolution

1. **Initiate Rebase**:
   ```bash
   git rebase upstream/quattro
   ```
2. **Resolve Conflicts with Invariant-First Policy**:
   - **Deleted Files**: If git flags a conflict because upstream modified a file that was deleted in our cleanup (e.g., `omarchy-upgrade-to-quattro`, `omarchy-restart-terminal`, non-retained themes), **do not keep upstream's changes**. Delete the file:
     ```bash
     git rm -f <path-to-deleted-file>
     ```
   - **Consolidated Configurations**: When conflicts arise in `bin/omarchy-theme-set`, `bin/omarchy-default-*`, `default/hypr/bindings/applications.lua`, or package lists, choose the workstation version preserving our single-tool architecture.
   - **Ambiguous Conflicts**: If an upstream change introduces a feature whose relevance to the workstation is unclear, **STOP AND ASK THE USER**.
3. **Continue Rebase**:
   ```bash
   git rebase --continue
   ```

### Phase 3: The Post-Rebase Clean-Merge Audit (Active Deletion)

Once `git rebase` completes successfully, you MUST perform the clean-merge audit to detect files that merged without conflict but violate workstation invariants:

1. **Run the Automated Invariant Audit**:
   ```bash
   default/agents/skills/workstation-rebase/scripts/audit-upstream.sh post
   ```
2. **Actively Delete Clean-Merged Bloat**:
   - **Purge Foreign Themes**: Delete any theme directory in `themes/` other than `everforest`, `last-horizon`, `matte-black`, `miasma`, `osaka-jade`.
   - **Purge Foreign Hardware**: Delete any newly added hardware scripts in `install/hardware/` outside `asus/proart-x870e.sh` and generic peripheral scripts.
   - **Purge Foreign Templates**: Delete any newly introduced templates in `default/themed/` for non-retained tools.
   - **Purge Foreign Icons & Assets**: Delete any newly introduced icons in `applications/icons/` or SVGs in `shell/plugins/agents/assets/` for non-retained apps.
3. **Re-run the Audit Script**:
   Ensure `audit-upstream.sh` outputs `✔ AUDIT PASSED! All workstation invariants are intact.`

### Phase 4: Full Test Suite Verification

Run the complete test suite to guarantee documentation and runtime integrity:

1. **Command Metadata**:
   ```bash
   bin/omarchy commands --check
   ```
2. **CLI Router Tests**:
   ```bash
   ./test/cli
   ```
3. **Shell Test Suite**:
   Run relevant unit and shell suites under `test/shell.d/`.
4. **Symlink Integrity**:
   ```bash
   find . -xtype l
   ```
   Must return 0 broken symlinks.

### Phase 5: User Confirmation & Origin Push

1. **Present Summary to User**:
   - Summarize upstream commits incorporated.
   - Summarize foreign additions actively deleted or pruned.
   - Present test verification results.
2. **Commit Post-Rebase Cleanups (if any)**:
   If active deletions were required after rebase, create a clean commit:
   ```bash
   git commit -m "cleanup: enforce workstation invariants after upstream rebase"
   ```
3. **Push to Origin (Upon Explicit Approval)**:
   Once the user approves, push the rebased branch to `origin/quattro`:
   ```bash
   git push --force-with-lease origin quattro
   ```
