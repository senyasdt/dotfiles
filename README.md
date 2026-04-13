# Dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

## Installation

Prerequisites:

```sh
command -v curl >/dev/null 2>&1 || {
  echo "curl is required"
  exit 1
}
```

Bootstrap everything with one command:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)"
```

Run with a specific profile:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)" -- full
```

Multiple profiles are also supported:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/senyasdt/dotfiles/master/bootstrap.sh)" -- full desktop
```

What the bootstrap script does:

- installs base dependencies needed to start (`git` on Linux via `apt`)
- passes selected profiles through `CHEZMOI_PROFILES`
- downloads and runs `chezmoi init --apply senyasdt`

Default profile:

```sh
full
```

## Manual chezmoi usage

If `chezmoi` is already installed:

```sh
CHEZMOI_PROFILES=full chezmoi init --apply senyasdt
```

With multiple profiles:

```sh
CHEZMOI_PROFILES=full,desktop chezmoi init --apply senyasdt
```

Apply changes later:

```sh
CHEZMOI_PROFILES=full chezmoi apply
```
