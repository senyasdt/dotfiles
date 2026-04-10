#!/usr/bin/env bash
set -e

echo "==> Installing oh-my-zsh"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  nix profile install nixpkgs#git
  git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
fi

git clone https://github.com/spaceship-prompt/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
