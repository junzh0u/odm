# odm — on-demand manager

A tiny package manager for prebuilt binaries from GitHub releases. One
self-contained zsh script: no daemon, no root, no runtime beyond `zsh`,
`curl`, `tar` (and `unzip` or `7z` for `.zip` assets).

Point it at a release archive; it installs just the binaries into a bin dir
of its own, remembers what it installed, and can cleanly uninstall and
upgrade later. The dir is odm's alone — everything in it belongs to a
package, and your other bin dirs are never touched.

```console
$ odm add just "https://github.com/casey/just/releases/download/{v}/just-{v}-x86_64-unknown-linux-musl.tar.gz"
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

That's how odm started — and here's what the one-liner doesn't give you:

- **Clean installs.** Release archives bundle READMEs, licenses, man pages,
  and completion scripts that all land next to your binaries. odm extracts to
  a temp dir and moves in **only the declared binaries** (zip archives too,
  via `unzip` or `7z`), into a dir it owns outright — your `~/.local/bin`
  stays yours.
- **Exact uninstalls.** A manifest records what each install added, so
  `uninstall` removes exactly that — nothing else.
- **Version awareness.** odm resolves the concrete version behind
  `releases/latest` and records it in a receipt; `list` shows installed vs
  latest at a glance and `upgrade` reinstalls only what's actually outdated.
  A cataloged tool that something else already provides on `PATH` shows as
  `external`.
- **A declarative catalog.** Packages live in one sourceable zsh file you can
  keep in your dotfiles — check it in, sync it across machines, and every
  host knows how to (re)install everything with one `odm install`/`upgrade`.
- **Install-on-first-use.** One line in your rc — `source <(odm init zsh)` —
  hooks `command_not_found_handler`: the first time you type `yazi` on a
  machine that doesn't have it, odm installs it and then runs it with your
  original arguments. Typing the command is the setup step.
- **Safety rails.** `-n` dry-runs any mutating command, failed downloads
  leave the previous install untouched, and archives that don't contain the
  expected binaries abort with a hint instead of half-installing.

## Install

Download [`odm`](./odm) anywhere on your `PATH` and `chmod +x` it. The
optional zsh completion is [`completions/_odm`](./completions/_odm).

## Commands

| Command | What it does |
|---|---|
| `odm add <pkg> <url>` | Register a package and install it |
| `odm remove <pkg>...` | Uninstall and unregister |
| `odm install [pkg...]` | Install registered packages (default: all of them) |
| `odm uninstall <pkg>...` | Remove installed files, keep the registration |
| `odm upgrade [pkg...]` | Reinstall what's outdated (default: everything installed) |
| `odm list` | All packages with installed vs latest versions |

`list` statuses: blank (up to date), `stale` (newer release available),
`external (<dir>)` (not odm-installed, but something else on `PATH` provides
the binaries), `not installed`.

Flags: `-f`/`--force` (reinstall / overwrite registration), `-n`/`--dry-run`,
`-b`/`--bins "cmd1 cmd2"` (with `add`, when the archive's commands differ from
the package name), `-q`/`-v`, `-h`.

## URLs and versions

Three URL shapes are understood:

- `.../releases/latest/download/<asset>` — for projects whose asset names are
  version-independent. Always fetches the latest; the concrete version is
  resolved (via the `releases/latest` redirect) and recorded for
  `list`/`upgrade` comparisons.
- `.../releases/download/{v}/asset-{v}.tar.gz` — for projects that embed the
  version in the tag path or asset filename (fzf, just, zoxide, …), where no
  version-independent URL exists. Every `{v}` expands to the latest release
  version — the tag from the `releases/latest` redirect, minus any leading
  `v` (write the tag's `v` literally in the URL where the project uses one,
  e.g. `.../download/v{v}/...`). If the lookup fails, `install`/`upgrade`
  fail loudly rather than guess.
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

- **Home** — `~/.local/share/odm` (override: `$ODM_HOME`) holds everything
  odm owns: `state/<pkg>/` with a `manifest` (installed file paths) and a
  `receipt` (version, URL, timestamp) per package, and `bin/` (override:
  `$ODM_BIN_DIR`) with the binaries, which `odm init zsh` puts on your
  `PATH`. Because only odm writes there, ownership is never ambiguous: no
  orphan files, no cleanup tooling needed. Migrating a machine that
  installed the same tools some other way is just `odm install` (everything
  lands in odm's dir, shadowing the old copies) followed by deleting the old
  copies whenever you get around to it.

## Auto-install on first use

Add one line to your `.zshrc` (or `.zshenv`, to cover scripts too):

```zsh
source <(odm init zsh)
```

It puts odm's bin dir on `PATH`, sources the catalog, and hooks
`command_not_found_handler`: the first time you type a cataloged command that
isn't installed, odm installs it and then runs it with your original
arguments. Anything not in the catalog still fails with the usual
`command not found` (exit 127). Prefer zero forks at shell startup?
`odm init zsh` just prints zsh — paste its output into your rc instead.

## Tests

```console
$ ./test/test-odm.zsh
```

Self-contained: stubs `curl`, builds fixture archives, touches nothing
outside a temp dir.
