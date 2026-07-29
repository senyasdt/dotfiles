# Workflow

## Profiles

- `lite` — headless / SSH / low-resource
- `full` — main CLI setup
- `desktop` — GUI layer on top of `full`

## Apply

Linux / macOS:

```sh
CHEZMOI_PROFILES=lite chezmoi apply
CHEZMOI_PROFILES=full chezmoi apply
CHEZMOI_PROFILES=full,desktop chezmoi apply
```

Windows PowerShell:

```powershell
$env:CHEZMOI_PROFILES="lite"
chezmoi apply
```

```powershell
$env:CHEZMOI_PROFILES="full"
chezmoi apply
```

```powershell
$env:CHEZMOI_PROFILES="full,desktop"
chezmoi apply
```

## Bootstrap

Linux / macOS:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)" -- lite
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)" -- full
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)" -- full desktop
```

Windows:

```powershell
$env:CHEZMOI_PROFILES="full,desktop"
chezmoi init --apply senyasdt
```

## Meaning

- `lite` keeps the machine headless and avoids GUI config
- `full` enables the full CLI setup with `nvim-full`
- `desktop` enables GUI config like `wezterm`, Windows Terminal, `komorebi`, `whkd`, Flow Launcher, AutoHotkey, and `vial`

## Editing

After changing a managed file on a machine:

```sh
chezmoi add <path>
chezmoi status --exclude externals
chezmoi diff --exclude externals
```

Then commit from the repo and apply only the needed paths:

```sh
chezmoi apply --force <path>
```

Before global apply, inspect run-scripts and external archive noise:

```sh
chezmoi status --exclude externals
chezmoi status --include externals
```

`R` status entries are run-scripts, not ordinary files. Run them only for intentional bootstrap or package updates.
