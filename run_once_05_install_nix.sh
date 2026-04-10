{{ if eq .chezmoi.os "linux-ubuntu" -}}
#!/bin/bash
if command -v apt >/dev/null 2>&1; then
  sudo apt update && sudo apt upgrade -y
fi
