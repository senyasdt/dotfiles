alias pbcopy='xclip -selection clipboard'
alias pbpaste='xclip -selection clipboard -o'
alias cat='bat -pp'
alias ch=chezmoi

if command -v eza >/dev/null; then
  alias ls="eza --long --all --group --icons=auto"
fi
