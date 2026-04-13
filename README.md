# Dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

## Installation

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

- installs base dependencies needed to start (`curl`, `git`, and `apt` bootstrap on Linux)
- writes selected chezmoi profiles into `.chezmoidata`
- downloads and runs `chezmoi init --apply senyasdt`

Default profile:

```sh
full
```

## Manual chezmoi usage

If `chezmoi` is already installed:

```sh
chezmoi init --apply senyasdt
```

Apply changes later:

```sh
chezmoi apply
```
