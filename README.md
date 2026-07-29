# Dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

This repository is a single cross-platform source of truth.

Profiles are intentionally split by machine type:

- `lite`: headless / SSH / low-resource machines
- `full`: main CLI setup with full Neovim
- `desktop`: GUI layer such as WezTerm, Windows Terminal, komorebi, whkd, Flow Launcher, AutoHotkey

Effective layout:

- shared: `wezterm`, `nvim`, `bat`, `navi`
- unix-only: `zsh`, bootstrap, package install hooks
- windows-only: PowerShell, Windows Terminal, `komorebi`, `whkd`, VS Code, Flow Launcher, `vial-helper`

Generated runtime files, logs, active themes, caches, and helper outputs are intentionally excluded.

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

## Windows

Install `chezmoi` natively on Windows and apply from PowerShell:

```powershell
chezmoi init --apply senyasdt
```

Or for an existing checkout:

```powershell
chezmoi apply
```

WSL is not required for Windows apply.

## Workflow

- Use exactly one profile set per machine: `lite`, `full`, or `full,desktop`.
- Edit shared config once in this repo.
- Run `chezmoi status --exclude externals` and `chezmoi diff --exclude externals` before `chezmoi apply`.
- Check external archive noise separately with `chezmoi status --include externals`.
- Use `chezmoi add <live-path>` when a live-file change should become source truth.
- Prefer targeted `chezmoi apply --force <live-path>` for drift cleanup.
- Treat `R` status entries as run-scripts; run them only during intentional bootstrap or package updates.
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
