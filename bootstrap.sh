#!/usr/bin/env bash
set -e

if command -v apt >/dev/null 2>&1; then
  SUDO=""
  [ "$EUID" -ne 0 ] && SUDO="sudo"

  $SUDO apt update
  $SUDO apt upgrade -y
  $SUDO apt install -y curl git
fi

mkdir -p .chezmoidata
printf "profiles: [%s]\n" "$(
  IFS=,
  echo "$*"
)" >~/.local/share/chezmoi/.chezmoidata/01_profiles.yaml

sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply senyasdt
