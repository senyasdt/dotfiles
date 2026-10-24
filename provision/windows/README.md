# Windows workstation restore

Source owner: `senyasdt/dotfiles`; detailed current-state inventory and decisions:
[project-documentation](https://github.com/senyasdt/project-documentation/tree/main/dotfiles/windows-workstation).

## New computer

Use native Windows PowerShell as the intended desktop user. Do not run the
whole restore as another administrator account: Scoop, HKCU and Startup belong
to the logged-in user. Package installers may request elevation separately.
Install Git/chezmoi with WinGet if missing, then initialize the explicit repo:

```powershell
winget install --id Git.Git --exact
winget install --id twpayne.chezmoi --exact
chezmoi init git@github.com:senyasdt/dotfiles.git
$src = chezmoi source-path
& "$src\provision\windows\restore.ps1" -Profiles full,desktop -Bar none
# Review the plan, then install packages, apply config and build/register helpers:
& "$src\provision\windows\restore.ps1" -Profiles full,desktop -Bar none -Apply
```

SSH access to GitHub must already work, or initialize with the HTTPS repository
URL using your normal Git authentication. Encrypted chezmoi assets require the
existing age recovery material; do not copy the identity into Git.

`restore.ps1` is plan-only without `-Apply`. It does not download MyDockFinder,
install layout DLLs, set up WinRM or start games. It excludes chezmoi external
archives during Windows apply. Re-run after sign-in/environment refresh if an
installer added commands to PATH. Keep the source directory until the process
finishes; installed helper paths are under `~/.config/desktop-customization`.

## Ownership and options

- `install.ps1 -Plan`: profile-aware package plan. `lite`/`full` have no desktop
  packages. komorebi/whkd use Scoop extras, matching the helper binary paths;
  do not also install the WinGet copies.
- `desktop.ps1 -Action Build`: compile the .NET Framework helpers after apply.
  `-Action Install`: build and register one **Desktop Session** Startup shortcut,
  plus **All Applications** in Start Menu. It does not start the desktop session.
- `Start-Session.ps1`: start the AHK manager, komorebi/whkd and six tray widgets.
  The AHK manager starts first, even if komorebi later fails. The tray icons also
  work without MyFinder, through the Windows tray.
- `WINDOWS_DESKTOP_BAR=none|yasb|mydockfinder` controls the rendered bar choice.
  `none` is the recovery baseline; YASB starts only for `yasb` and its configured
  bar is enabled only for that choice. MyDockFinder is an optional Steam install
  using its own startup/preferences. Selecting it does not install or launch it.
  This setting does not stop an already-running bar or disable old scheduled tasks.
- `script-launcher/config.json`: grouped AHK rules, deduplication, last-blocker
  resume with 15-second delay, persistent per-script manual toggles. Runtime
  state/logs/binaries remain outside Git. Rules observe processes once per second;
  they cannot guarantee completion before the first anti-cheat check.
- `Open-AppLibrary.ps1`, `.config/open-app-library.cmd` and **All Applications**
  open `shell:AppsFolder`, without a daemon, AHK or dock. The Win-tap AHK helper
  uses MyDockFinder Alt+F12 while it runs, and AppsFolder otherwise. During games
  the AHK helper is stopped; the independent shortcut remains available.
- komorebi uses its normal local data directory by default. The repaired junction
  on HOMEPC is a host workaround, not a requirement for every computer. To opt in,
  set `komorebi-support/settings.json` runtimeJunction to true after inspecting
  existing data. The helper refuses to replace a different directory/junction.

Persisted user environment variables keep later native Windows apply consistent.
To change the bar permanently, set both the process and user
`WINDOWS_DESKTOP_BAR`, inspect `chezmoi diff`, and apply the specific desktop/YASB
targets. `-Bar yasb` on restore also installs YASB. It does not uninstall other bars.

## Existing HOMEPC: migrate deliberately

The 24 October running helpers still use `WorkingFolder/desktop-customization`.
This source update alone does not switch them or move the komorebi junction.
Do not run a global chezmoi apply on this machine before reviewing the diff.

1. Save current Startup/task definitions and AHK runtime manual state. The first
   migration's backups are in `WorkingFolder/desktop-customization/script-launcher/backup`.
2. Finish the prepared admin cleanup there for `Vial Layer Daemon`, the duplicate
   `Vial Helper Daemon` task and `YASB Reborn`. Keep the native Vial Startup entry.
3. Stop old FinderWidgets and ScriptLauncher through their old Manage.ps1 files.
   Launcher Stop leaves AHK scripts running. Remove backed-up old AHK/Finder/YASB
   Startup entries; the provisioner refuses duplicates instead of deleting them.
4. Review chezmoi diff and apply desktop, AHK, wrappers and komorebi files. The
   source removes old autohotkey/komorebi/yasb Startup targets; chezmoi forgetting
   source files does not by itself remove their live copies. Review/remove the
   old komorebi.cmd separately before activating Desktop Session.
5. Run desktop.ps1 Install; transfer only the intended manual toggles, not stale
   test paths. Start-Session explicitly or sign in again. Verify there is one
   owner per helper and Alt+1/Alt+2 work. The old komorebi junction may remain at
   its existing target; do not move/delete its active socket directory.

## Remaining manual recovery material

- Native Vial helper and ZMK helper: install/build from their source repositories;
  this installer reports their presence but does not claim to install them.
  Startup wrappers assume `%LOCALAPPDATA%/Programs/vial-helper/run-hidden.ps1`
  and `%LOCALAPPDATA%/Programs/zmk-yasb/zmk-helperd.exe` plus per-user configs.
  The Vial vendor installer also registers a scheduled task. Keep exactly one
  login owner: with the dotfiles Vial Startup wrapper, disable that duplicate
  task explicitly after exporting it, or omit/remove the wrapper if choosing
  the vendor task. Do not assume both are needed. YASB additionally needs the
  `yasb-state-reader.exe` shipped by the Vial release integration; no binary is
  stored in dotfiles. The native helpers/readers are manual prerequisites until
  release versions and hashes have been selected and tested.
- Hardware VIDs/PIDs, selected keyboards, layer labels and firmware versions need
  review on new hardware. Do not clone all of AppData or flash firmware blindly.
- Custom Technical AltGr layouts need their trusted installers/source first.
  `desktop.ps1 -IncludeLayoutGuard -Action Build` can build the optional cleanup
  helper; run its Install.ps1 only after both expected custom layouts exist.
  The default restore does not activate this host-specific helper.
- VPN widget authorization is DPAPI-bound under `%APPDATA%/router-vpn-yasb`.
  Re-enroll a new Windows user with the homelab client procedure; copying the
  encrypted file is not a working recovery mechanism. No token belongs in Git.
- Optional weather API authorization is rendered from `WEATHER_API_KEY`; the
  literal value found in the live YAML was not retained in the new template.
  Set it through private per-user environment/recovery material if needed.
- MyDockFinder preferences, Steam entitlement/sign-in and tray pinning remain
  interactive. Keep it optional; do not import the entire machine-specific INI.

## Verification

Syntax parsing, isolated builds and launcher logic tests were run locally on
24 October 2026. Profile rendering checks cover Linux/macOS/Windows.
No clean Windows VM restore or package installation was performed in this audit.
Check new-machine runtime with desktop.ps1 Status, launcher runtime/status.json,
FinderWidgets status.json, komorebic state and physical keyboard shortcuts.

Ansible remains the Linux/macOS and homelab orchestrator. Windows can later be
managed from a Linux controller over PSRP/WinRM or SSH, invoking these same native
scripts in the correct user context. For a single personal PC, the native restore
entry avoids adding a controller and remote-session desktop differences.

## Optional Catppuccin profile (branch yasb-catppuccin)

`restore.ps1 -Profiles full,desktop -Bar yasb -Theme catppuccin` previews the
choice; add `-Apply` for provisioning and activation. Existing HOMEPC should use
the already installed profile's Apply/Rollback commands, not run a global restore
over its legacy helpers and active komorebi junction.

The profile provides a top panel, smart bottom dock, populated Launchpad with integrated search, AHK controls, keyboard states and VPN callbacks. MyDockFinder and
its FinderWidgets are stopped and backed-up login entries disabled. It keeps
komorebi, BSP and the AHK game rules. Theme outputs are excluded from ordinary
chezmoi apply while WINDOWS_DESKTOP_THEME=catppuccin; Manage.ps1 owns them.
Desktop Session starts the profile, without adding a second profile Startup
shortcut on clean installations. Do not delete its private rollback directory.

See the [profile guide](../../dot_config/desktop-customization/yasb-catppuccin/README.md)
for installation, all shortcuts, both rollback paths and the actual validation
limits. Current profile requires YASB 2.0.7 or newer; all three configuration
variants pass the 2.0.7 schema. An existing older YASB is upgraded by install.ps1
before activation. update.ps1 preserves WINDOWS_DESKTOP_THEME on preview/apply.
No clean VM/reboot test is claimed. Ansible remains the Unix provisioning layer;
this native Windows path owns the desktop. For an existing HOMEPC, use the
targeted package upgrade and profile Refresh instead of a global restore.
