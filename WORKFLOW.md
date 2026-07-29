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

The bootstrap flow is:

1. install `chezmoi`
2. `chezmoi init`
3. run `provision/ansible/site.yml`
4. `chezmoi apply`

Windows:

```powershell
$env:CHEZMOI_PROFILES="full,desktop"
chezmoi init senyasdt
cd "$(chezmoi source-path)"
powershell.exe -ExecutionPolicy Bypass -File .\provision\windows\install.ps1
chezmoi apply
```

## Meaning

- `lite` keeps the machine headless and avoids GUI config
- `full` enables the full CLI setup with `nvim-full`
- `desktop` enables GUI config. Windows desktop uses `komorebi`/`komorebic`,
  `whkd`, YASB, AutoHotkey, Flow Launcher, and `vial`. macOS desktop uses
  AeroSpace and Karabiner-Elements.

## Provisioning

Linux / macOS packages and toolchains are installed by Ansible:

```sh
CHEZMOI_PROFILES=full,desktop ansible-playbook -i localhost, provision/ansible/site.yml
```

Windows packages and desktop apps are installed by PowerShell:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\provision\windows\install.ps1
```

Updates use explicit provision-and-apply scripts:

```sh
CHEZMOI_PROFILES=full,desktop provision/update.sh
```

```powershell
$env:CHEZMOI_PROFILES="full,desktop"
powershell.exe -ExecutionPolicy Bypass -File .\provision\windows\update.ps1
```

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
