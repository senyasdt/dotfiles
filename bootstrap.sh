#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 ]]; then
  c_reset=$'\033[0m'
  c_red=$'\033[1;31m'
  c_green=$'\033[1;32m'
  c_yellow=$'\033[1;33m'
  c_blue=$'\033[1;34m'
  c_magenta=$'\033[1;35m'
  c_cyan=$'\033[1;36m'
  c_white=$'\033[1;37m'
else
  c_reset=''
  c_red=''
  c_green=''
  c_yellow=''
  c_blue=''
  c_magenta=''
  c_cyan=''
  c_white=''
fi

log() {
  printf '%s==>%s %s\n' "$c_cyan" "$c_reset" "$*"
}

log_ok() {
  printf '%s[ok]%s %s\n' "$c_green" "$c_reset" "$*"
}

log_warn() {
  printf '%s[warn]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2
}

log_err() {
  printf '%s[err]%s %s\n' "$c_red" "$c_reset" "$*" >&2
}

cleanup() {
  if [[ -n ${tmp_script:-} && -f ${tmp_script:-} ]]; then
    rm -f "$tmp_script"
  fi
}

print_logo() {
  printf '%s' "$c_magenta"
  printf ' ██████╗██╗  ██╗███████╗███████╗███╗   ███╗ ██████╗ ██╗\n'
  printf '██╔════╝██║  ██║██╔════╝╚══███╔╝████╗ ████║██╔═══██╗██║\n'
  printf '██║     ███████║█████╗    ███╔╝ ██╔████╔██║██║   ██║██║\n'
  printf '██║     ██╔══██║██╔══╝   ███╔╝  ██║╚██╔╝██║██║   ██║██║\n'
  printf '╚██████╗██║  ██║███████╗███████╗██║ ╚═╝ ██║╚██████╔╝██║\n'
  printf ' ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚═╝\n'
  printf '%s' "$c_reset"
  printf '%sBootstrap%s profiles: %s\n' "$c_white" "$c_reset" "${*:-full}"
}

trap 'log_err "Bootstrap failed on line $LINENO."' ERR
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_err "Required command not found: $1"
    exit 1
  fi
}

print_logo "$@"

profiles=("$@")
if [[ ${#profiles[@]} -eq 0 ]]; then
  profiles=(full)
fi

sudo_cmd=()
if [[ ${EUID} -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  sudo_cmd=(sudo)
fi

if [[ ${EUID} -ne 0 ]] && [[ ${#sudo_cmd[@]} -eq 0 ]] && command -v apt-get >/dev/null 2>&1; then
  log_err "apt-get requires root or sudo"
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  log "Preparing base packages with APT"
  "${sudo_cmd[@]}" apt-get update
  DEBIAN_FRONTEND=noninteractive "${sudo_cmd[@]}" apt-get install -y curl git
  log_ok "Base packages are ready"
fi

repo_dir="${HOME}/.local/share/chezmoi"
data_dir="${repo_dir}/.chezmoidata"
profiles_file="${data_dir}/01_profiles.yaml"

mkdir -p "$data_dir"
printf 'profiles: [%s]\n' "$(
  IFS=,
  printf '%s' "${profiles[*]}"
)" >"$profiles_file"
log_ok "Saved selected profiles to $profiles_file"

require_cmd curl
tmp_script="$(mktemp)"

log "Downloading chezmoi installer"
curl -fsSL 'https://get.chezmoi.io' -o "$tmp_script"

log "Running chezmoi init"
sh "$tmp_script" -- init --apply senyasdt
log_ok "chezmoi bootstrap completed"
