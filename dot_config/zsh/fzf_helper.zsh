export FZF_CTRL_R_OPTS="
  --bind 'ctrl-y:execute-silent(echo -n {2..} | (xclip -selection clipboard 2>/dev/null || pbcopy || wl-copy))+abort'
  --color header:italic
  --header 'Press CTRL-Y to copy command into clipboard'"

export FZF_ALT_C_OPTS="--preview '(eza --tree --level=2 --color=always --icons=always {} || ls -F --color=always {}) | head -200' \
  --preview-window 'right:50%' \
  --bind 'ctrl-/:toggle-preview' \
  --header 'Folders Tree (CTRL-/ to hide)' \
  --walker-skip .git,node_modules,target"

export FZF_CTRL_T_OPTS="--preview '
  if [ -d {} ]; then
    (eza --tree --level=2 --icons=always --color=always {} || ls -F --color=always {}) | head -200
  else
    (bat --color=always {} || cat {}) | head -200
  fi' 
  --preview-window 'right:50%' 
  --bind 'ctrl-/:toggle-preview' 
  --header 'Folders Tree (CTRL-/ to hide)' \
  --walker-skip .git,node_modules,target"

