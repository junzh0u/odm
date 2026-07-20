# odm — on-demand manager

A tiny package manager for prebuilt binaries from GitHub releases. One
self-contained zsh script: no daemon, no root, no runtime beyond `zsh`,
`curl`, `tar` (and `unzip` or `7z` for `.zip` assets).

Point it at a release archive; it installs just the binaries into a bin dir
it owns outright, remembers what it installed, and can cleanly uninstall and
upgrade later — your other bin dirs are never touched.

```console
$ odm add just "https://github.com/casey/just/releases/download/{v}/just-{v}-x86_64-unknown-linux-musl.tar.gz"
[odm] installing just 1.55.1...
[odm] installed just 1.55.1

$ odm list
PACKAGE  AUTHOR  BINS  INSTALLED  LATEST  STATUS
just     casey   just  1.55.1     1.56.0  stale

$ odm upgrade
[odm] installing just 1.56.0...
[odm] installed just 1.56.0
```

## Why not just `curl | tar -C ~/.local/bin`?

That's how odm started. The one-liner doesn't give you:

- **Clean installs** — only the declared binaries are moved in (extracted
  via a temp dir), not the READMEs, licenses, and man pages that release
  archives bundle.
- **Exact uninstalls** — a manifest records what each install added, so
  `uninstall` removes exactly that.
- **Version awareness** — the concrete version behind `releases/latest` is
  resolved and recorded; `list` shows installed vs latest, `upgrade`
  reinstalls only what's outdated.
- **A declarative catalog** — one sourceable zsh file, checked into your
  dotfiles; any host reinstalls everything with one `odm install`.
- **Install-on-first-use** — `source <(odm init zsh)` hooks
  `command_not_found_handler`: the first time you type a cataloged command,
  odm installs it and then runs it with your original arguments.
- **Safety rails** — `-n` dry-runs any mutating command; failed downloads
  and archives missing the expected binaries abort without touching the
  previous install.

## Install

Download [`odm`](./odm) anywhere on your `PATH` and `chmod +x` it. Optional
zsh completion: [`completions/_odm`](./completions/_odm).

## Commands

| Command | What it does |
|---|---|
| `odm add <pkg> <url>` | Register a package and install it |
| `odm remove <pkg>...` | Uninstall and unregister |
| `odm install [pkg...]` | Install registered packages (default: all) |
| `odm uninstall <pkg>...` | Remove installed files, keep the registration |
| `odm upgrade [pkg...]` | Reinstall what's outdated (default: everything installed) |
| `odm list` | All packages with installed vs latest versions |

`list` statuses: blank (up to date), `stale` (newer release available),
`external (<dir>)` (not odm-installed, but something else on `PATH` provides
the binaries), `not installed`.

Flags: `-f`/`--force` (reinstall / overwrite registration), `-n`/`--dry-run`,
`-b`/`--bins "cmd1 cmd2"` (with `add`, when the archive's commands differ
from the package name), `-q`/`-v`, `-h`.

## URLs and versions

- `.../releases/latest/download/<asset>` — for version-independent asset
  names. Always fetches the latest; the concrete version is resolved from
  the `releases/latest` redirect and recorded.
- `.../releases/download/{v}/asset-{v}.tar.gz` — for projects that embed the
  version in the tag or filename (fzf, just, zoxide, …). `{v}` expands to
  the latest tag minus any leading `v` (write that `v` literally where the
  project uses one, e.g. `.../download/v{v}/...`). If the lookup fails,
  `install`/`upgrade` fail loudly rather than guess.
- Any other https `.tar.gz`/`.tgz`/`.zip` URL — works, but the version shows
  as `unknown`, so `upgrade` reinstalls it each time.

## Files

- **Catalog** — `~/.config/odm/packages.zsh` (override: `$ODM_CATALOG`).
  Plain zsh, rewritten wholesale by odm, safe and cheap to `source` from a
  shell rc:

  ```zsh
  typeset -gA _odm_packages=(
      [yazi]="https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip"
  )
  typeset -gA _odm_bins=(    # only when the commands differ from the package name
      [yazi]="ya yazi"
  )
  ```

- **Home** — `~/.local/share/odm` (override: `$ODM_HOME`): `state/<pkg>/`
  with a `manifest` (installed file paths) and a `receipt` (version, URL,
  timestamp) per package, plus `bin/` (override: `$ODM_BIN_DIR`), which
  `odm init zsh` puts on your `PATH`. Only odm writes there, so ownership is
  never ambiguous — no orphan files, no cleanup tooling.

## Auto-install on first use

Add one line to your `.zshrc` (or `.zshenv`, to cover scripts too):

```zsh
source <(odm init zsh)
```

It puts odm's bin dir on `PATH`, sources the catalog, and hooks
`command_not_found_handler`; anything not in the catalog still fails with
the usual `command not found` (exit 127). Prefer zero forks at shell
startup? `odm init zsh` just prints zsh — paste its output into your rc.

## Tests

```console
$ ./test/test-odm.zsh
```

Self-contained: stubs `curl`, builds fixture archives, touches nothing
outside a temp dir.
