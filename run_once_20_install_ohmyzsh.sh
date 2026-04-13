#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 ]]; then
  c_reset=$'\033[0m'
  c_green=$'\033[1;32m'
  c_cyan=$'\033[1;36m'
  c_yellow=$'\033[1;33m'
else
  c_reset=''
  c_green=''
  c_cyan=''
  c_yellow=''
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

log "Installing oh-my-zsh extras"

# if [ ! -d "$HOME/.oh-my-zsh" ]; then
#   git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
# fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.config/zsh}"

if [ ! -d "$ZSH_CUSTOM/themes/spaceship-prompt" ]; then
  log "Cloning spaceship prompt"
  git clone https://github.com/spaceship-prompt/spaceship-prompt.git \
    "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1

  ln -sf \
    "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" \
    "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
  log_ok "Spaceship prompt installed"
else
  log_warn "Spaceship prompt is already installed"
fi

if command -v zsh >/dev/null 2>&1; then
  current_shell="${SHELL:-}"
  zsh_path="$(command -v zsh)"
  if [[ "$current_shell" != "$zsh_path" ]]; then
    log "Changing default shell to $zsh_path"
    chsh -s "$zsh_path"
    log_ok "Default shell updated"
  else
    log_warn "Default shell is already set to zsh"
  fi
fi
