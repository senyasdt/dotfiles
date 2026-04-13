zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'

zstyle ':completion:*:*:-command-:*:*' group-order alias builtins functions commands
zstyle ':completion:*:complete:git-rebase:*' group-order 'commits'
zstyle ':completion:*:*:git-checkout:*' group-order main-branches upstream-branches tags

# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
# set descriptions format to enable group support
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no
# preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:cd:*' fzf-preview '
if (( $+commands[eza] )); then
  eza -1 --color=always -- "$realpath"
elif ls --color=always . >/dev/null 2>&1; then
  ls -1 --color=always -- "$realpath"
else
  ls -1 -- "$realpath"
fi
'
# custom fzf flags
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
# To make fzf-tab follow FZF_DEFAULT_OPTS.
zstyle ':fzf-tab:*' use-fzf-default-opts yes
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'

zstyle ':fzf-tab:complete:-command-:*' fzf-preview '(( $+commands[tldr] )) && tldr "$word" || man "$word"'
