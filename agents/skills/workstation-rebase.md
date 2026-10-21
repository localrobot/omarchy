# Workstation Rebase Guide

Read this before rebasing or synchronizing local branches (`quattro`, `origin/quattro`) with `upstream/quattro`.

This workstation build is tailored specifically for:

- ASUS ProArt X870E-CREATOR WIFI motherboard
- AMD Ryzen 9 9900X CPU
- Headless NVIDIA RTX 5060 Ti AI Accelerator
- Consolidated toolset: Foot terminal, Google Chrome browser, VS Code & Neovim editors, 5 retained themes (`everforest`, `last-horizon`, `matte-black` [default], `miasma`, `osaka-jade`), and FOSS local workflow (zero non-retained AI agents or commercial apps).

## Core Rebase Mandate

Rebasing is **not** merely replaying commits or resolving git merge conflicts. An upstream commit may introduce new hardware support, new themes, or new tools that merge without any conflict. The rebase procedure requires **actively auditing and deleting** newly introduced files and code that violate workstation invariants.

When an upstream change is ambiguous or its utility to the workstation is unclear, **stop and ask the user** before proceeding.

## Detailed Procedure

### 1. Pre-Rebase Audit

- Ensure working tree is clean: `git status`.
- Fetch upstream: `git fetch upstream quattro`.
- Inspect incoming upstream commits:
  ```bash
  git log --oneline HEAD..upstream/quattro
  git diff --name-status HEAD...upstream/quattro | grep '^A' || true
  ```

### 2. Interactive Rebase

- Start rebase: `git rebase upstream/quattro`.
- In conflict resolution:
  - If upstream touched a file that was deleted during workstation cleanup (e.g., `omarchy-upgrade-to-quattro`, `omarchy-restart-terminal`, non-retained themes), delete it with `git rm -f <path>`. Do not allow git to restore deleted files.
  - If a conflict touches default configurations (terminal, editor, browser, themes, hardware), keep the workstation's consolidated choice.
  - If ambiguous, ask the user.

### 3. Clean-Merge Audit (Active Deletion)

After the rebase finishes, execute the automated invariant audit:

```bash
default/agents/skills/workstation-rebase/scripts/audit-upstream.sh post
```

Actively delete any clean-merged additions:

- Foreign hardware scripts in `install/hardware/` outside `asus/proart-x870e.sh` and generic peripheral scripts.
- Foreign themes in `themes/` outside the 5 retained themes.
- Foreign templates in `default/themed/` for non-retained tools.
- Foreign icons or assets in `applications/icons/` or `shell/plugins/agents/assets/`.

### 4. Test Suite Verification

- Verify command metadata: `bin/omarchy commands --check`.
- Verify CLI routing: `./test/cli`.
- Verify shell tests: run relevant tests under `test/shell.d/`.
- Verify symlinks: `find . -xtype l` (must return zero broken links).

### 5. Push to Origin

- Only push after full verification passes and the user confirms:
  ```bash
  git push --force-with-lease origin quattro
  ```

For the exhaustive matrix of allowed vs forbidden components, refer to [`default/agents/skills/workstation-rebase/references/workstation-invariants.md`](../../default/agents/skills/workstation-rebase/references/workstation-invariants.md).
