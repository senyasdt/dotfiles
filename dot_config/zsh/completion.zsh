zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'

zstyle ':completion:*' completer _complete _complete:all
zstyle ':completion:*:*:git-checkout:*' group-order main-branches upstream-branches tags

# zstyle ':completion:*:*:-command-:*' tag-order \
#     'builtin-commands' \
#     'functions' \
#     'aliases' \
#     'commands' \
#     '*'
#
zstyle ':completion:*:*:-command-:*' group-order \
    'builtin command' \
    'shell function' \
    alias \
    'external command'

zstyle ':completion:*:*:-command-:*:commands' ignored-patterns \
    '*.dll' '*.DLL' '*.nls' '*.NLS'
# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
# set descriptions format to enable group support
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no
# preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
# custom fzf flags
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
# To make fzf-tab follow FZF_DEFAULT_OPTS.
zstyle ':fzf-tab:*' use-fzf-default-opts yes
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'

zstyle ':fzf-tab:complete:-command-:*' fzf-preview 'tldr $word || man $word'
