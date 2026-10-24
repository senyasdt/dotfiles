# Provisioning

`chezmoi` owns dotfiles. Provisioning owns packages, applications, toolchains,
and OS-level setup.

## Linux and macOS

Run the local Ansible playbook from the chezmoi source repo:

```sh
CHEZMOI_PROFILES=full,desktop ansible-playbook -i localhost, provision/ansible/site.yml
```

Profiles keep the same meaning as in `chezmoi`:

- `lite` - headless / SSH / low-resource
- `full` - CLI workstation
- `full,desktop` - GUI workstation

macOS desktop installs AeroSpace and Karabiner-Elements. Windows desktop uses
komorebi/komorebic, whkd, YASB, and AutoHotkey.

## Windows

Run the explicit PowerShell provisioner from the chezmoi source repo:

```powershell
& .\provision\windows\restore.ps1 -Profiles full,desktop -Bar none # plan; -Apply to execute
```

After provisioning, apply dotfiles with the selected profile:

```powershell
$env:CHEZMOI_PROFILES="full,desktop"
chezmoi apply
```

## Updates

Linux / macOS:

```sh
CHEZMOI_PROFILES=full,desktop provision/update.sh
```

Windows:

```powershell
$env:CHEZMOI_PROFILES="full,desktop"
powershell.exe -ExecutionPolicy Bypass -File .\provision\windows\update.ps1
```

Windows recovery, optional bars, helper builds and manual checkpoints are described in [windows/README.md](windows/README.md). Windows update.ps1 requires -Apply to pull/provision/apply and refuses a dirty source checkout. Unix update behavior is unchanged.
