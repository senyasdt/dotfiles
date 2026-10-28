Portable komorebi startup

Start-DesktopWM.ps1 resolves Scoop executables first, then PATH, starts komorebi directly with the user config, waits for IPC, and starts whkd. Repeated start checks existing instances. Stop/Restart use komorebic stop --whkd without forced termination.

Start/Stop/Restart share a per-session mutex. CLI requests have a 4-second timeout; a timeout terminates only that request, never the daemon. Startup waits for IPC and verifies that whkd remains running.

On an opted-in junction installation only, if a newly started daemon exits with socket bind error 10048, the launcher retries once after recreating the verified junction with its same target. It requires no komorebi process in any session, preserves the old link beside it, never moves or deletes runtime data, and refuses ordinary directories or unexpected targets. A healthy daemon is never restarted to repair a link. The underlying Windows failure is not established; HOMEPC recovered after the existing junction was recreated on 2026-10-27. No TCP listener is enabled.

Default settings.json: runtimeJunction=false. A fresh computer uses komorebi's normal data directory. HOMEPC's existing junction workaround is documented separately and is not created on every machine.

Opt-in runtimeJunction=true requires the local komorebi data directory to be absent or already pointing to the expected sibling komorebi-runtime folder. Existing different directories are never moved or deleted by this script. Do not move an active socket directory.

Installation uses provision/windows/desktop.ps1 and Desktop Session.lnk; do not create a parallel komorebi.cmd Startup entry. Logs and socket data are not source configuration.
