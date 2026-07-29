#!/usr/bin/env bash
set -Eeuo pipefail

profiles="${CHEZMOI_PROFILES:-full}"
if [[ $# -gt 0 ]]; then
  profiles="$(IFS=,; printf '%s' "$*")"
fi

chezmoi_bin="${CHEZMOI_BIN:-chezmoi}"
source_dir="$("$chezmoi_bin" source-path)"

git -C "$source_dir" pull --ff-only

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook is required for provisioning updates" >&2
  exit 1
fi

CHEZMOI_PROFILES="$profiles" ansible-playbook -i localhost, "$source_dir/provision/ansible/site.yml"
CHEZMOI_PROFILES="$profiles" "$chezmoi_bin" apply
