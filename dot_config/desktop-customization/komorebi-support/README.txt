Portable komorebi startup

Start-DesktopWM.ps1 resolves Scoop executables first, then PATH, starts komorebi directly with the user config, waits for IPC, and starts whkd. Repeated start checks existing instances. Stop/Restart use komorebic stop --whkd without forced termination.

Default settings.json: runtimeJunction=false. A fresh computer uses komorebi's normal data directory. HOMEPC's existing junction workaround is documented separately and is not created on every machine.

Opt-in runtimeJunction=true requires the local komorebi data directory to be absent or already pointing to the expected sibling komorebi-runtime folder. Existing different directories are never moved or deleted by this script. Do not move an active socket directory.

Installation uses provision/windows/desktop.ps1 and Desktop Session.lnk; do not create a parallel komorebi.cmd Startup entry. Logs and socket data are not source configuration.