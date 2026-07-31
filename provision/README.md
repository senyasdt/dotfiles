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

The `full` profile installs a platform-native Docker runtime:

- Debian / Ubuntu: Docker Engine from Docker's official APT repository,
  including Buildx and the Compose plugin. The service is enabled and the
  provisioned user is added to the `docker` group.
- macOS: Docker Desktop through the `docker-desktop` Homebrew cask.
- Windows: Docker Desktop through the `Docker.DockerDesktop` WinGet package.

Linux group membership takes effect after signing out and back in. Docker
Desktop may request permissions on its first launch.

The `full` profile also installs `mise` for versions of Java, Go, Node.js,
Python, and other development tools. Zsh uses `mise activate`; native Windows
uses Scoop's mise shims. The managed global mise config selects Temurin Java 21
as the workstation default. Choose other versions per project, for example:

```sh
mise use java@temurin-17 go@latest
```

Use `mise use -g ...` only when another machine-wide default is intentional.

macOS desktop installs AeroSpace and Karabiner-Elements. Windows desktop uses
komorebi/komorebic, whkd, YASB, and AutoHotkey.

## Windows

Run the explicit PowerShell provisioner from the chezmoi source repo:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\provision\windows\install.ps1
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

These scripts pull the source repo, run provisioning, and apply dotfiles.
