# odm — on-demand manager

A tiny package manager for prebuilt binaries from GitHub releases. One
self-contained zsh script: no daemon, no root, no runtime beyond `zsh`,
`curl`, `tar` (and `unzip` or `7z` for `.zip` assets).

Point it at a release archive; it installs just the binaries into
`~/.local/bin`, remembers what it installed, and can cleanly uninstall and
upgrade later.

```console
$ odm add just "https://github.com/casey/just/releases/download/{v:1.55.1}/just-{v}-x86_64-unknown-linux-musl.tar.gz"
[odm] installing just 1.55.1...
[odm] installed just 1.55.1

$ odm list
PACKAGE  BINS  INSTALLED  LATEST  STATUS
just     just  1.55.1     1.56.0  stale

$ odm upgrade
[odm] installing just 1.56.0...
[odm] installed just 1.56.0
```

## Why not just `curl | tar -C ~/.local/bin`?

Release tarballs bundle READMEs, licenses, man pages, and completion scripts
that all land next to your binaries. odm extracts to a temp dir, moves in
**only the declared binaries**, and writes a manifest so `uninstall` removes
exactly what `install` added — nothing else.

## Install

Download [`odm`](./odm) anywhere on your `PATH` and `chmod +x` it. The
optional zsh completion is [`completions/_odm`](./completions/_odm).

## Commands

| Command | What it does |
|---|---|
| `odm add <pkg> <url>` | Register a package and install it |
| `odm remove <pkg>...` | Uninstall and unregister |
| `odm install <pkg>...` | Install registered packages |
| `odm uninstall <pkg>...` | Remove installed files, keep the registration |
| `odm upgrade [pkg...]` | Reinstall what's outdated (default: everything installed) |
| `odm list` | All packages with installed vs latest versions |

Flags: `-f`/`--force` (reinstall / overwrite registration), `-n`/`--dry-run`,
`-b`/`--bins "cmd1 cmd2"` (with `add`, when the archive's commands differ from
the package name), `-q`/`-v`, `-h`.

## URLs and versions

Three URL shapes are understood:

- `.../releases/latest/download/<asset>` — always fetches the latest; the
  concrete version is resolved (via the `releases/latest` redirect) and
  recorded for `list`/`upgrade` comparisons.
- `.../releases/download/{v:1.2.3}/asset-{v}.tar.gz` — templated: `{v:X}`
  resolves to the latest release tag, falling back to the pinned `X` when the
  lookup fails (offline-friendly); `{v}` repeats the resolved version. After a
  successful install of a newer version, odm bumps the pin in the catalog so
  the fallback stays fresh.
- Any other https `.tar.gz`/`.tgz`/`.zip` URL — works, but the version shows
  as `unknown`, so `upgrade` reinstalls it each time.

## Files

- **Catalog** — `~/.config/odm/packages.zsh` (override: `$ODM_CATALOG`).
  Plain zsh definitions, rewritten wholesale by odm, safe and cheap to
  `source` from a shell rc:

  ```zsh
  typeset -gA _odm_packages=(
      [yazi]="https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip"
  )
  typeset -gA _odm_bins=(    # only when the commands differ from the package name
      [yazi]="ya yazi"
  )
  ```

- **State** — `~/.local/share/odm/<pkg>/` (override: `$ODM_STATE_DIR`) holds a
  `manifest` (installed file paths) and a `receipt` (version, URL, timestamp).
  A binary installed before odm existed shows as `legacy` in `list`; running
  `odm upgrade` adopts it.

- **Binaries** — `~/.local/bin` (override: `$ODM_BIN_DIR`).

## Auto-install on first use

Because the catalog is sourceable zsh, a `command_not_found_handler` can
install packages the moment they're first invoked:

```zsh
source ~/.config/odm/packages.zsh

function command_not_found_handler() {
    local cmd=$1; shift
    local pkg
    for pkg in ${(k)_odm_bins}; do
        (( ${${=_odm_bins[$pkg]}[(Ie)$cmd]} )) && break
        pkg=
    done
    : ${pkg:=${_odm_packages[$cmd]:+$cmd}}
    if [[ -z $pkg ]] || ! odm install $pkg; then
        print -u2 "zsh: command not found: $cmd"
        return 127
    fi
    rehash
    command $cmd "$@"
}
```

## Tests

```console
$ ./test/test-odm.zsh
```

Self-contained: stubs `curl`, builds fixture archives, touches nothing
outside a temp dir.
