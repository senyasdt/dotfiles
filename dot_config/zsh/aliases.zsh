alias ch=chezmoi

if command -v xclip >/dev/null 2>&1; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
elif command -v wl-copy >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
  alias pbcopy='wl-copy'
  alias pbpaste='wl-paste'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat -pp'
elif command -v batcat >/dev/null 2>&1; then
  alias cat='batcat -pp'
fi

if command -v eza >/dev/null; then
  alias ls="eza --long --all --group --icons=auto"
fi
