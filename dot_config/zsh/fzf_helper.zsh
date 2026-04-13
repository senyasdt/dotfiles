export FZF_CTRL_R_OPTS="
  --bind 'ctrl-y:execute-silent(echo -n {2..} | (xclip -selection clipboard 2>/dev/null || pbcopy || wl-copy))+abort'
  --color header:italic
  --header 'Press CTRL-Y to copy command into clipboard'"

export FZF_ALT_C_OPTS="--preview '
  if command -v eza >/dev/null 2>&1; then
    eza --tree --level=2 --color=always --icons=always -- {}
  elif ls --color=always . >/dev/null 2>&1; then
    ls -F --color=always -- {}
  else
    ls -F -- {}
  fi | head -200' \
  --preview-window 'right:50%' \
  --bind 'ctrl-/:toggle-preview' \
  --header 'Folders Tree (CTRL-/ to hide)' \
  --walker-skip .git,node_modules,target"

export FZF_CTRL_T_OPTS="--preview '
  if [ -d {} ]; then
    if command -v eza >/dev/null 2>&1; then
      eza --tree --level=2 --icons=always --color=always -- {}
    elif ls --color=always . >/dev/null 2>&1; then
      ls -F --color=always -- {}
    else
      ls -F -- {}
    fi
  else
    if command -v bat >/dev/null 2>&1; then
      bat --color=always -- {}
    elif command -v batcat >/dev/null 2>&1; then
      batcat --color=always -- {}
    else
      cat -- {}
    fi
  fi' 
  --preview-window 'right:50%' 
  --bind 'ctrl-/:toggle-preview' 
  --header 'Folders Tree (CTRL-/ to hide)' \
  --walker-skip .git,node_modules,target"
