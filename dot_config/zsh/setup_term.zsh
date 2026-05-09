bindkey -v
KEYTIMEOUT=15
bindkey -M viins 'jj' vi-cmd-mode

set_cursor_shape() {
  case "$1" in
    block) printf '\e[2 q' ;;
    bar) printf '\e[6 q' ;;
  esac
}

wezterm_set_user_var() {
  [[ "${TERM_PROGRAM:-}" == "WezTerm" ]] || return
  command -v base64 >/dev/null 2>&1 || return
  local value
  value="$(printf "%s" "$2" | base64 | tr -d '\n')"

  if [[ -n "${TMUX:-}" ]]; then
    printf "\033Ptmux;\033\033]1337;SetUserVar=%s=%s\007\033\\" "$1" "$value"
  else
    printf "\033]1337;SetUserVar=%s=%s\007" "$1" "$value"
  fi
}

wezterm_update_vi_mode() {
  local mode="I"

  case "${KEYMAP:-main}" in
    vicmd)
      mode="N"
      set_cursor_shape block
      ;;
    *)
      set_cursor_shape bar
      ;;
  esac

  wezterm_set_user_var "VI_MODE" "$mode"
}

autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init wezterm_update_vi_mode
add-zle-hook-widget keymap-select wezterm_update_vi_mode

autoload -Uz add-zsh-hook
add-zsh-hook precmd wezterm_update_vi_mode

wezterm_update_vi_mode

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh --cmd cd)"
fi

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi
