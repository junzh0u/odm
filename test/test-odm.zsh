#!/usr/bin/env zsh
#
# Automated odm test suite — no network, no HOME pollution: every odm run gets
# ODM_CATALOG/ODM_STATE_DIR/ODM_BIN_DIR inside a tmpdir plus a `curl` stub
# first on PATH. The stub serves a canned latest-release redirect (STUB_LATEST)
# and a fixture archive (STUB_ARCHIVE) built by the tests.

setopt err_exit

odm=${0:A:h:h}/odm

failures=0

function log_info()  { print -u2 -r -- "[test] $*" }
function log_error() { print -u2 -r -- "[test] $*" }

function assert_exit_code() {
    local description=$1 expected=$2 actual=$3
    if (( actual == expected )); then
        log_info "PASS: $description"
    else
        log_error "FAIL: $description (expected exit $expected, got $actual)"
        (( ++failures ))
    fi
}

function assert_exists() {
    local description=$1 filepath=$2
    if [[ -e $filepath ]]; then
        log_info "PASS: $description"
    else
        log_error "FAIL: $description (expected to exist: $filepath)"
        (( ++failures ))
    fi
}

function assert_not_exists() {
    local description=$1 filepath=$2
    if [[ ! -e $filepath ]]; then
        log_info "PASS: $description"
    else
        log_error "FAIL: $description (expected absent: $filepath)"
        (( ++failures ))
    fi
}

function assert_equals() {
    local description=$1 expected=$2 actual=$3
    if [[ $actual == $expected ]]; then
        log_info "PASS: $description"
    else
        log_error "FAIL: $description (expected '$expected', got '$actual')"
        (( ++failures ))
    fi
}

function assert_contains() {
    local description=$1 haystack=$2 needle=$3
    if [[ $haystack == *$needle* ]]; then
        log_info "PASS: $description"
    else
        log_error "FAIL: $description (expected to contain '$needle'; got: $haystack)"
        (( ++failures ))
    fi
}

function assert_not_contains() {
    local description=$1 haystack=$2 needle=$3
    if [[ $haystack != *$needle* ]]; then
        log_info "PASS: $description"
    else
        log_error "FAIL: $description (expected NOT to contain '$needle'; got: $haystack)"
        (( ++failures ))
    fi
}

# ── Sandbox ────────────────────────────────────────────────────────

# The curl stub must be executable, but /tmp may be mounted noexec (e.g.
# Synology DSM) — probe, and fall back to a tmpdir under $HOME.
tmp=$(mktemp -d -t test_odm.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
print -r -- '#!/bin/sh' > $tmp/exec-probe
chmod +x $tmp/exec-probe
if ! $tmp/exec-probe 2>/dev/null; then
    rm -rf $tmp
    mkdir -p $HOME/.cache
    tmp=$(mktemp -d $HOME/.cache/test_odm.XXXXXX)
fi
catalog=$tmp/catalog.zsh
state=$tmp/state
bindir=$tmp/bin
mkdir -p $tmp/stubs $tmp/fixtures $bindir

cat > $tmp/stubs/curl <<'EOF'
#!/usr/bin/env zsh
# Test stub for curl. See test-odm.zsh.
case $1 in
    -sI)
        [[ -n ${STUB_LATEST:-} ]] || exit 0
        print -r -- "HTTP/2 302"
        print -r -- "location: https://github.com/stub/repo/releases/tag/v$STUB_LATEST"$'\r'
        ;;
    -fsSL)
        [[ -r ${STUB_ARCHIVE:-} ]] || exit 22
        if [[ ${3:-} == -o ]]; then
            cat -- $STUB_ARCHIVE > $4
        else
            cat -- $STUB_ARCHIVE
        fi
        ;;
    *)
        print -u2 "curl stub: unexpected args: $@"
        exit 1
        ;;
esac
EOF
chmod +x $tmp/stubs/curl

stub_latest=
stub_archive=
output=
code=0

function run_odm() {
    code=0
    output=$(ODM_CATALOG=$catalog ODM_STATE_DIR=$state ODM_BIN_DIR=$bindir \
        STUB_LATEST=$stub_latest STUB_ARCHIVE=$stub_archive \
        PATH=$tmp/stubs:$PATH zsh $odm $@ 2>&1) || code=$?
}

function make_exe() {
    local file=$1 marker=$2
    mkdir -p ${file:h}
    print -r -- "#!/bin/sh" > $file
    print -r -- "echo $marker" >> $file
    chmod +x $file
}

function make_tar() {
    local out=$1 src=$2
    tar czf $out -C $src .
}

function catalog_keys() {
    zsh -c "source $catalog 2>/dev/null; print -r -- \${(ok)_odm_packages}"
}

# ── Test: add installs only declared binary ────────────────────────

log_info "── add: selective install, manifest, receipt ──"

src=$tmp/fixtures/foo-src
make_exe $src/nested/foo v1
print -r -- "readme" > $src/README.md
print -r -- "license" > $src/LICENSE
make_exe $src/foo.bash completion  # executable spillage that must not install
chmod +x $src/LICENSE              # spillage with exec bit
make_tar $tmp/fixtures/foo.tar.gz $src

stub_latest=1.0.0
stub_archive=$tmp/fixtures/foo.tar.gz
run_odm add foo https://github.com/stub/repo/releases/latest/download/foo.tar.gz
assert_exit_code "add foo succeeds" 0 $code
assert_exists "foo binary installed" $bindir/foo
assert_not_exists "README.md not installed" $bindir/README.md
assert_not_exists "LICENSE not installed" $bindir/LICENSE
assert_not_exists "foo.bash not installed" $bindir/foo.bash
assert_equals "manifest lists exactly the installed file" "$bindir/foo" "$(<$state/foo/manifest)"
assert_contains "receipt records resolved version" "$(<$state/foo/receipt)" "version=1.0.0"
assert_contains "catalog registered foo" "$(<$catalog)" '[foo]="https://github.com/stub/repo/releases/latest/download/foo.tar.gz"'

# ── Test: duplicate add ────────────────────────────────────────────

log_info "── add: duplicate registration ──"

run_odm add foo https://github.com/stub/repo/releases/latest/download/other.tar.gz
assert_exit_code "duplicate add exits 12" 12 $code
run_odm add -f foo https://github.com/stub/repo/releases/latest/download/foo.tar.gz
assert_exit_code "add -f overwrites" 0 $code

# ── Test: URL validation ───────────────────────────────────────────

run_odm add badurl http://github.com/stub/repo/releases/latest/download/x.tar.gz
assert_exit_code "non-https URL rejected" 2 $code
run_odm add badurl https://github.com/stub/repo/releases/latest/download/x.deb
assert_exit_code "non-archive URL rejected" 2 $code

# ── Test: multi-bin package ────────────────────────────────────────

log_info "── add -b: multi-binary package ──"

src=$tmp/fixtures/multi-src
make_exe $src/pkg-1.0/cpx cpx-v1
make_exe $src/pkg-1.0/mvx mvx-v1
make_tar $tmp/fixtures/multi.tar.gz $src

stub_archive=$tmp/fixtures/multi.tar.gz
run_odm add mvx https://github.com/stub/repo/releases/latest/download/mvx.tar.gz -b "cpx mvx"
assert_exit_code "add -b succeeds" 0 $code
assert_exists "cpx installed" $bindir/cpx
assert_exists "mvx installed" $bindir/mvx
assert_contains "catalog records bins" "$(<$catalog)" '[mvx]="cpx mvx"'
assert_equals "manifest has both files" "$bindir/cpx
$bindir/mvx" "$(<$state/mvx/manifest)"

# ── Test: unknown package ──────────────────────────────────────────

run_odm install nosuchpkg
assert_exit_code "install of unregistered package exits 10" 10 $code

# ── Test: uninstall removes exactly manifest files ─────────────────

log_info "── uninstall / remove ──"

print -r -- "decoy" > $bindir/decoy
run_odm uninstall mvx
assert_exit_code "uninstall succeeds" 0 $code
assert_not_exists "cpx removed" $bindir/cpx
assert_not_exists "mvx removed" $bindir/mvx
assert_not_exists "state dir removed" $state/mvx
assert_exists "unrelated file survives" $bindir/decoy
assert_contains "registration kept after uninstall" "$(catalog_keys)" mvx

run_odm uninstall mvx
assert_exit_code "uninstall of not-installed package is a no-op success" 0 $code

# ── Test: remove unregisters ───────────────────────────────────────

run_odm remove mvx
assert_exit_code "remove succeeds" 0 $code
assert_equals "only foo remains registered" foo "$(catalog_keys)"
run_odm remove mvx
assert_exit_code "remove of unregistered package exits 10" 10 $code

# ── Test: {v:pin} template resolution and pin bump ─────────────────

log_info "── {v:pin} templates ──"

src=$tmp/fixtures/tool-src
make_exe $src/tool tool-v2
make_tar $tmp/fixtures/tool.tar.gz $src

stub_latest=2.0.0
stub_archive=$tmp/fixtures/tool.tar.gz
run_odm add tool "https://github.com/stub/repo/releases/download/v{v:1.0.0}/tool-{v}.tar.gz"
assert_exit_code "templated add succeeds" 0 $code
assert_contains "receipt has resolved version" "$(<$state/tool/receipt)" "version=2.0.0"
assert_contains "receipt url has version substituted" "$(<$state/tool/receipt)" "url=https://github.com/stub/repo/releases/download/v2.0.0/tool-2.0.0.tar.gz"
assert_contains "catalog pin bumped to resolved version" "$(<$catalog)" '{v:2.0.0}'

stub_latest=  # simulate lookup failure -> pinned fallback
run_odm install -f tool
assert_exit_code "fallback install succeeds" 0 $code
assert_contains "fallback used pinned version" "$(<$state/tool/receipt)" "version=2.0.0"
assert_contains "pin not rewritten by fallback" "$(<$catalog)" '{v:2.0.0}'

# ── Test: upgrade ──────────────────────────────────────────────────

log_info "── upgrade ──"

stub_latest=2.0.0
run_odm upgrade tool
assert_exit_code "upgrade up-to-date succeeds" 0 $code
assert_contains "upgrade reports up to date" "$output" "up to date"

make_exe $src/tool tool-v3
make_tar $tmp/fixtures/tool.tar.gz $src
stub_latest=3.0.0
run_odm upgrade tool
assert_exit_code "upgrade to newer succeeds" 0 $code
assert_contains "receipt bumped" "$(<$state/tool/receipt)" "version=3.0.0"
assert_contains "binary replaced" "$(<$bindir/tool)" tool-v3

run_odm upgrade tool
assert_contains "no reinstall when current" "$output" "up to date"
run_odm upgrade -f tool
assert_contains "forced reinstall" "$output" "installed tool"

# ── Test: legacy adoption via bare upgrade ─────────────────────────

log_info "── legacy adoption ──"

run_odm uninstall foo   # keep foo registered but out of bare upgrade's targets
rm -rf $state/tool  # simulate a pre-odm install: binary present, no state
run_odm upgrade
assert_exit_code "bare upgrade succeeds" 0 $code
assert_exists "legacy package adopted (receipt written)" $state/tool/receipt
assert_contains "legacy package reinstalled" "$(<$state/tool/receipt)" "version=3.0.0"

# ── Test: dry run ──────────────────────────────────────────────────

log_info "── dry run ──"

run_odm uninstall tool
before_catalog=$(<$catalog)
run_odm -n install tool
assert_exit_code "dry-run install succeeds" 0 $code
assert_contains "dry-run reports" "$output" "would install"
assert_not_exists "dry-run installs nothing" $bindir/tool
assert_not_exists "dry-run writes no state" $state/tool
run_odm -n add dry https://github.com/stub/repo/releases/latest/download/foo.tar.gz
assert_equals "dry-run add leaves catalog untouched" $before_catalog "$(<$catalog)"

# ── Test: archive missing declared bin ─────────────────────────────

log_info "── missing declared bin ──"

stub_archive=$tmp/fixtures/foo.tar.gz  # contains 'foo', not 'bar'
run_odm add bar https://github.com/stub/repo/releases/latest/download/bar.tar.gz
assert_exit_code "missing declared bin exits 13" 13 $code
assert_contains "error names the missing bin" "$output" "no executable named: bar"
run_odm remove bar  # registration intentionally survives the failed install
assert_exit_code "cleanup of failed add" 0 $code

# ── Test: zip archives (needs 7z or unzip) ─────────────────────────

if (( $+commands[7z] || $+commands[zip] )); then
    log_info "── zip archives ──"
    src=$tmp/fixtures/zip-src
    make_exe $src/pkg/zeta zeta-v1
    print -r -- "readme" > $src/pkg/README.md
    if (( $+commands[zip] )); then
        (cd $src && zip -qr $tmp/fixtures/zeta.zip .)
    else
        (cd $src && 7z a -tzip $tmp/fixtures/zeta.zip . > /dev/null)
    fi
    stub_archive=$tmp/fixtures/zeta.zip
    run_odm add zeta https://github.com/stub/repo/releases/latest/download/zeta.zip
    assert_exit_code "zip add succeeds" 0 $code
    assert_exists "zip binary installed" $bindir/zeta
    assert_not_exists "zip spillage not installed" $bindir/README.md
else
    log_info "SKIP: zip tests (no 7z or zip available)"
fi

# ── Test: list ─────────────────────────────────────────────────────

log_info "── list ──"

stub_latest=9.9.9
run_odm list
assert_exit_code "list succeeds" 0 $code
assert_contains "list marks stale package" "$output" stale
assert_contains "list marks uninstalled package" "$output" "not installed"

# A registered-but-uninstalled package whose bin exists elsewhere on PATH
# (here: the stubs dir) is marked external, with the providing directory.
make_exe $tmp/stubs/foo foo-external
run_odm list
assert_contains "list marks externally provided package" "$output" "external ($tmp/stubs)"
rm -f $tmp/stubs/foo
run_odm list
assert_not_contains "external marker gone with the external bin" "$output" external

# ── Test: usage errors ─────────────────────────────────────────────

run_odm
assert_exit_code "missing command exits 2" 2 $code
run_odm frobnicate
assert_exit_code "unknown command exits 2" 2 $code
run_odm list extra-arg
assert_exit_code "list with args exits 2" 2 $code
run_odm install -b "x" foo
assert_exit_code "-b outside add exits 2" 2 $code

# ── Summary ────────────────────────────────────────────────────────

if (( failures )); then
    log_error "$failures assertion(s) FAILED"
    exit 1
fi
log_info "all tests passed"
