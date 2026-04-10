#!/usr/bin/env bash
set -e

echo "==> Installing Nix"

if ! command -v nix &>/dev/null; then
  sh <(curl -L https://nixos.org/nix/install) --daemon
fi

# загрузка nix
. /etc/profile.d/nix.sh || true

echo "==> Enabling flakes"
run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # Мы уже root, выполняем команду как есть
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    # Мы не root, но sudo установлен — используем его
    sudo "$@"
  else
    # Мы не root и sudo нет — пробуем su или выходим с ошибкой
    echo "Ошибка: требуются права root, но sudo не найден." >&2
    exit 1
  fi
}
run_as_root mkdir -p /etc/nix
echo "experimental-features = nix-command flakes" | run_as_root tee /etc/nix/nix.conf
