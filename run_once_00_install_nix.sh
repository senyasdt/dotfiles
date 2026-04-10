#!/usr/bin/env bash
set -e

echo "==> Installing Nix"

if ! command -v nix &>/dev/null; then
  sh <(curl -L https://nixos.org/nix/install) --daemon
fi

# загрузка nix
. /etc/profile.d/nix.sh || true

echo "==> Enabling flakes"

sudo mkdir -p /etc/nix
echo "experimental-features = nix-command flakes" | sudo tee /etc/nix/nix.conf
