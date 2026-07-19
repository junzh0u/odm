# CLAUDE.md — odm

Self-contained zsh package manager for prebuilt GitHub-release binaries.
See README.md for user-facing behavior.

## Conventions

- **`odm` stays a single self-contained file** — depends only on zsh, curl,
  tar, and unzip-or-7z. No sourcing of other files from this repo; helpers are
  inlined. (Same philosophy as junzh0u/git-smartlog.)
- `completions/_odm` must stay in sync with the flag/verb surface — update it
  whenever options or commands change.
- Custom exit codes start at 10 and are documented in `usage`; `2` is wrong
  usage. Keep README, `usage`, and the completion aligned.
- Never name a variable `status` (read-only zsh special) or `path` (shadows
  `$path`).

## Testing

```console
$ ./test/test-odm.zsh
```

- No network: a `curl` stub on PATH serves a canned `releases/latest` redirect
  (`STUB_LATEST`) and fixture archives (`STUB_ARCHIVE`).
- No HOME pollution: every odm invocation gets `ODM_CATALOG`/`ODM_STATE_DIR`/
  `ODM_BIN_DIR` inside the test tmpdir.
- The tmpdir must be exec-capable for the stub: `/tmp` is mounted noexec on
  some systems (e.g. Synology DSM), so the suite probes and falls back to
  `~/.cache`.

## Environment notes

- Synology DSM (a primary deployment target) ships `7z` but not `unzip` —
  keep the zip fallback chain.
- BusyBox tar handles `tar xzf -` from stdin; `$pipestatus[1]` is checked so
  a failed `curl` isn't masked by tar exiting 0 on a truncated-but-valid
  prefix.
