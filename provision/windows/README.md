# Windows workstation restore

Source owner: `senyasdt/dotfiles`. The target stack is **YASB + stock komorebi/whkd
+ ScriptLauncher**. MyDockFinder and FinderWidgets are retired from provisioning
and startup. The experimental native Scrolling build stays on `komorebi-scrolling`.
See [all integration changes](CHANGES.md) and
[workstation documentation](https://github.com/senyasdt/project-documentation/tree/main/dotfiles/windows-workstation).

## New computer

Use native Windows PowerShell as the intended desktop user. Package installers
may request elevation separately; do not provision Scoop/HKCU/Startup as another
administrator account. Git authentication and age recovery material must already
be available; private identities do not belong in this repository.

```powershell
winget install --id Git.Git --exact
winget install --id twpayne.chezmoi --exact
chezmoi init git@github.com:senyasdt/dotfiles.git
$src = chezmoi source-path
# Review package/configuration plan:
& "$src\provision\windows\restore.ps1" -Profiles full,desktop -Bar yasb -Theme catppuccin
# After reviewing source status and chezmoi diff:
& "$src\provision\windows\restore.ps1" -Profiles full,desktop -Bar yasb -Theme catppuccin -Apply
```

The historical `catppuccin` profile name now denotes the cold translucent grey
palette. A minimal recovery alternative is `-Bar none -Theme classic`.
The script defaults remain plan-only, none/classic; YASB requires explicit choice.
Until the integration PR is merged, select branch `windows-desktop-integration`
explicitly when reviewing it; the published master still has its previous setup.

`restore.ps1` installs the selected packages, applies chezmoi without externals,
builds/registers the helpers and activates the chosen YASB profile. It does not
install Steam, MyDockFinder, keyboard-layout DLLs, Vial/ZMK releases, or WinRM.
Rerun after refreshing PATH if an installer added commands unavailable to the
current shell. Helpers live under `~/.config/desktop-customization`.

## Ownership and options

- `install.ps1 -Plan` is read-only. `lite` has CLI basics; `full` retains upstream
  mise and Docker Desktop; `full,desktop` adds desktop packages and komorebi/whkd.
  An explicit `-Profiles` argument overrides the inherited process environment.
- Supported bars are `none|yasb`. `-Bar yasb` installs YASB 2.0.7 or newer.
  Cold Grey uses YASB's own application library; Flow Launcher is excluded from
  that package plan. Classic remains available as a compatibility profile.
- `desktop.ps1 -Action Install` builds ScriptLauncher and registers one
  **Desktop Session** Startup shortcut and **All Applications** in Start Menu.
  It refuses conflicting legacy Startup entries. FinderWidgets is not required,
  built, deployed or started. Its old source remains only for historical rollback.
- `Start-Session.ps1` starts the AHK manager first, then komorebi/whkd and the
  selected YASB panel. Cold Grey starts DesktopBridge for dock policy/status menus;
  classic uses the same checked Start-Yasb launch path. No second bar is launched.
- The top panel includes workspaces/layout, AHK/Vial/ZMK, VPN, weather, media,
  language, sound and tray. The bottom dock shows the library and running/pinned
  applications; pins belong to the user. No fixed Explorer/Terminal pins are added.
- `Start-Yasb.ps1` normalizes IPC paths/CLI lookup and checks access before Manage
  stops a working bar. Native YASB reconnect handles WM restarts. All three YAML
  variants include Scrolling in ActiveLayout's list to avoid its 2.0.7 rotate loop.
- `script-launcher/config.json` maps script groups to blocker processes. It
  deduplicates scripts, remembers manual disables and resumes only after the last
  blocker plus the configured 15-second delay. The legacy filename
  `mydockfinder-hotkeys.ahk` is retained to preserve saved rules/manual state; it
  contains no MyDockFinder integration. The managed YASB override handles Win-tap;
  Win+E and other chords retain their meaning. AHK is fully stopped during blockers.
  Polling cannot guarantee completion before the first anti-cheat check.
- YASB's library is available by mouse and Alt+F12 without AHK. **All Applications**
  opens Windows `shell:AppsFolder` without any dock or background process.
- komorebi uses the normal local data directory. HOMEPC's junction repair is a
  local workaround, opt-in via settings; the helper refuses foreign directories.

## Existing HOMEPC migration

The current installation uses WorkingFolder helpers and an experimental native
WM. This source/PR does not modify those processes or apply the new target profile.
Do not run global chezmoi apply over it without inspecting the complete diff.

1. Export Startup/task definitions and save ScriptLauncher manual state and
   YASB private snapshots. Keep existing backups and the active IPC junction.
2. Review old duplicate Vial/YASB tasks and remove only backed-up duplicate
   login owners. The native Vial helper must retain exactly one startup owner.
3. Stop old helpers explicitly from their current folders before changing their
   installation root. Remove backed-up conflicting Startup links, including old
   MyDockFinder/Finder entries. The provisioner refuses them instead of silently
   deleting them. A source-file removal alone does not remove its old live target.
4. Inspect chezmoi diff; apply only reviewed desktop targets, build/register one
   Desktop Session and transfer intended manual toggles. Never copy stale PIDs,
   test paths, active sockets or the entire AppData tree.
5. Verify one helper per role, Alt+1/Alt+2, application library, dock hide/reveal
   and AHK off/manual states. Returning from the experimental native WM is a
   separate deliberate action; it is not performed by this integration branch.

MyDockFinder is neither uninstalled nor deleted from an existing computer by
this change. Historical profile snapshots and explicit rollback commands remain
usable; their old labels do not describe a supported new-machine configuration.

## Manual recovery material

- Vial/ZMK helpers/readers require reviewed source releases and hashes. Existing
  wrappers expect `%LOCALAPPDATA%/Programs/vial-helper/run-hidden.ps1` and
  `%LOCALAPPDATA%/Programs/zmk-yasb/zmk-helperd.exe`. With the Vial Startup wrapper,
  explicitly disable/export a duplicate vendor task or choose that task instead.
  Firmware, device VIDs/PIDs and keyboard labels require hardware-specific review.
- Technical AltGr layout installers are separate. The optional cleanup helper
  can be built with `desktop.ps1 -IncludeLayoutGuard -Action Build`; installation
  is explicit and requires both approved custom layouts already present.
- VPN authorization is bound to the Windows user with DPAPI. Re-enroll a new user;
  encrypted files copied from another profile are not a working recovery method.
- Cold Grey weather uses free Open-Meteo. Coordinates/cache and any alternative
  provider credentials remain private; home-router VPN rules are not restored by
  the desktop installer. See the weather runbook for network requirements.
- Chrome uses the standard owner-selected appearance. No custom extension,
  new-tab replacement, browser profile edit or GPU mode is applied.

## Appearance and rollback

The Cold Grey restore also applies the
[shared application palette](../../dot_config/desktop-customization/appearance/README.md)
to VS Code, Windows Terminal and WezTerm. It merges appearance keys, saves exact
bytes with SHA256 and refuses to overwrite later conflicting edits on Restore.
The YASB profile has its own private snapshot and explicit rollback commands.
Keep them private and outside Git. There is no forced graphics reset or GPU disable.

## Validation and automation limits

`Test-Desktop.ps1` checks package plans, explicit-profile precedence, PowerShell
syntax, 40 launcher assertions, 23 appearance rollback checks and isolated native
helper builds/policies. The Python profile checks cover Linux/macOS/Windows and
both bars/themes; optional schema validation uses YASB 2.0.7. These checks do not
install packages, run real AHK, talk to keyboard HID or change the current desktop.
No clean Windows VM install, reboot or fresh-account restore is claimed.

Ansible remains the Linux/macOS provisioner. Windows reuses the native user-context
scripts; adding a controller/WinRM for one personal PC is not required. A future
controller can invoke the same entry after addressing interactive-session scope.
`update.ps1` previews by default, requires clean source before `-Apply`, performs
only a fast-forward pull, then invokes restore while preserving bar/theme choices.
