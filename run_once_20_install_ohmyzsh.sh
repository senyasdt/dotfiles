#!/usr/bin/env bash
set -e

echo "==> Installing oh-my-zsh"

# if [ ! -d "$HOME/.oh-my-zsh" ]; then
#   git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
# fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.config/zsh}"

if [ ! -d "$ZSH_CUSTOM/themes/spaceship-prompt" ]; then
  git clone https://github.com/spaceship-prompt/spaceship-prompt.git \
    "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1

  ln -sf \
    "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" \
    "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
fi

chsh -s $(which zsh)
