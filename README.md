# Dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

This repository is a single cross-platform source of truth.

Profiles are intentionally split by machine type:

- `lite`: headless / SSH / low-resource machines
- `full`: main CLI setup with full Neovim
- `desktop`: GUI layer such as WezTerm, Windows Terminal, komorebi, whkd, Flow Launcher, AutoHotkey

Effective layout:

- shared: `wezterm`, `nvim`, `bat`, `navi`
- unix-only: `zsh`, bootstrap, shell/editor config
- windows-only: PowerShell, Windows Terminal, `komorebi`/`komorebic`, `whkd`,
  VS Code, Flow Launcher, YASB, AutoHotkey, `vial-helper`
- macOS desktop: AeroSpace and Karabiner-Elements

Generated runtime files, logs, active themes, caches, and helper outputs are intentionally excluded.

Provisioning is split from dotfiles:

- `provision/ansible/site.yml` installs Linux/macOS packages, apps, and
  toolchains.
- `provision/windows/install.ps1` installs Windows packages and desktop apps.
- `chezmoi apply` applies files only.

## Quick Start

Use exactly one profile set per machine type:

| Machine type | Command |
| --- | --- |
| Headless / SSH / low RAM | `CHEZMOI_PROFILES=lite chezmoi apply` |
| CLI workstation | `CHEZMOI_PROFILES=full chezmoi apply` |
| GUI workstation | `CHEZMOI_PROFILES=full,desktop chezmoi apply` |

Windows PowerShell:

```powershell
$env:CHEZMOI_PROFILES="lite"
chezmoi apply
```

or:

```powershell
$env:CHEZMOI_PROFILES="full,desktop"
chezmoi apply
```

## Linux / macOS bootstrap

Prerequisites:

```sh
command -v curl >/dev/null 2>&1 || {
  echo "curl is required"
  exit 1
}
```

Bootstrap installs `chezmoi` into `~/.local/bin`, initializes the source repo,
runs `provision/ansible/site.yml`, then applies dotfiles.

Bootstrap with:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)"
```

With a specific profile:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)" -- full
```

For a GUI workstation:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)" -- full desktop
```

Update an existing Linux/macOS machine:

```sh
CHEZMOI_PROFILES=full,desktop "$(chezmoi source-path)/provision/update.sh"
```

## Windows

**master: LeopardWM + YASB Cold Grey.** The `komorebi` branch keeps the same
panel and helpers with stock komorebi/whkd. MyDockFinder is retired.

Personal English/Russian Technical AltGr keyboards: [simple manual setup](provision/windows/keyboard-layouts/README.md).

```powershell
chezmoi init https://github.com/senyasdt/dotfiles.git
$src = chezmoi source-path
& "$src\provision\windows\restore.ps1" -Profiles full,desktop
# Review the plan and source diff, then:
& "$src\provision\windows\restore.ps1" -Profiles full,desktop -Apply
```

[Windows restore](provision/windows/README.md) covers installation prerequisites,
pinned LeopardWM, login ownership, the alternate branch, rollback and private
recovery material. Native PowerShell handles Windows; Ansible handles Linux/macOS.
The current release includes the application library, cold translucent dock,
per-app widths and atomic AHK ON/OFF with game rules. See the
[release changes and validation limits](provision/windows/RELEASE-2026-10-28.md).
Existing HOMEPC uses legacy WorkingFolder helper paths: inspect the complete diff
and follow its migration instructions before applying a new root.

## Workflow

- Use exactly one profile set per machine: `lite`, `full`, or `full,desktop`.
- Edit shared config once in this repo.
- Put packages and OS setup in `provision/`, not in `chezmoi` run-scripts.
- Run `chezmoi status --exclude externals` and `chezmoi diff --exclude externals` before `chezmoi apply`.
- Check external archive noise separately with `chezmoi status --include externals`.
- Use `chezmoi add <live-path>` when a live-file change should become source truth.
- Prefer targeted `chezmoi apply --force <live-path>` for drift cleanup.
- Use `lite` for Raspberry Pi, servers, and SSH-only boxes.
- Add `desktop` only on machines that actually need GUI config.

## Profiles

Default profile:

```sh
full
```

Multiple profiles are supported:

```sh
CHEZMOI_PROFILES=full,desktop chezmoi apply
```

Headless / SSH machine:

```sh
CHEZMOI_PROFILES=lite chezmoi apply
```
