# Keyboard Conformance (v0.2.0) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `tuin_choose`, `tuin_menu`, `tuin_confirm`, and `tuin_input` behave like every other terminal program a keyboard-heavy user already knows, with a real PTY test suite behind them.

**Architecture:** Two private helpers carry all the terminal mechanics: `_tuin_readkey` turns raw bytes on fd 3 into one normalized token, and `_tuin_tty_enter`/`_tuin_tty_leave` own raw mode, cursor, and signal traps. The four interactive primitives are rebuilt on those. Nothing public changes shape.

**Tech Stack:** bash 3.2 builtins, `stty`, ANSI/ECMA-48 escapes, bats-core 1.11 with a `script(1)`-based PTY harness. Zero new dependencies.

**Design of record:** `docs/plans/2026-09-03-keyboard-conformance-design.md`.

**Hard rules for every task:**
- No `eval`, no `sh -c`, no `bash -c`, no `${!var}` inside `tuin.sh`. Task 10 adds a test that fails the build if one appears.
- No bash 4 features: no `mapfile`, `declare -A`, `read -i`, `${var,,}`, `&>>`.
- Every global tuin introduces is `_TUIN_*` or `_tuin_*` and is initialized at source time so `set -u` callers survive.
- Run `make test` and `make lint` before every commit. Both must be green.
- Run tests with the system bash on macOS: `PATH=/bin:/usr/bin:$PATH make test`.

Two decisions that differ from the design doc, both for the no-`eval` rule:
1. Caller traps cannot be restored without `eval` (that is what `trap -p` output needs). So tuin installs its own INT/TERM/TSTP/CONT/WINCH traps while a primitive is active and resets them to default afterwards, which is what v0.1.0 already did for INT/TERM. For EXIT, tuin installs a trap only if the caller has none, and leaves a caller's EXIT trap untouched.
2. `tuin_menu` remembers the cursor for the most recently shown title only, not per title. That is the whole common case (one menu in a loop) in four lines instead of a hand-rolled map.

---

### Task 1: PTY test harness

**Files:**
- Create: `tests/test_helper/pty.bash`
- Create: `tests/test_pty_harness.bats`

**Step 1: Write the harness**

```bash
#!/usr/bin/env bash
# PTY harness for BATS. Runs a bash snippet under script(1) with a real
# pseudo-terminal so tuin's interactive paths (fd 3 on /dev/tty, stty,
# cursor escapes) exercise the same code a human hits.
#
#   tuin_pty <keys-printf-format> -- <bash snippet>
#
# After the call:
#   $pty_status  exit status of the snippet
#   $pty_out     what the snippet wrote to stdout (trailing newlines stripped)
#   $pty_tty     everything drawn on the terminal
#
# Keys are fed 0.3 s after start and stdin is held open for $TUIN_PTY_TAIL
# seconds afterwards (default 1.5, long enough for bash 3.2's 1 s ESC delay).

_tuin_pty_script() {  # <logfile> <command>
    if script --version >/dev/null 2>&1; then
        script -qec "$2" "$1"          # util-linux
    else
        script -q "$1" "$2"            # BSD / macOS
    fi
}

tuin_pty() {
    local keys="$1"; shift
    [[ "${1:-}" == "--" ]] && shift
    local snippet="$1"
    local dir="$BATS_TEST_TMPDIR"
    local wrapper="$dir/wrapper.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        "source '$TUIN_SH'" \
        "{ $snippet ; } > '$dir/out'" \
        "echo \$? > '$dir/status'" > "$wrapper"
    chmod +x "$wrapper"
    : > "$dir/out"; : > "$dir/status"; : > "$dir/tty"

    (
        sleep 0.3
        # shellcheck disable=SC2059  # keys is deliberately a printf format
        printf "$keys"
        sleep "${TUIN_PTY_TAIL:-1.5}"
    ) | TERM=xterm NO_COLOR=1 _tuin_pty_script "$dir/tty" "$wrapper" >/dev/null 2>&1

    pty_status=$(cat "$dir/status")
    pty_out=$(cat "$dir/out")
    pty_tty=$(cat "$dir/tty")
}
```

`NO_COLOR=1` keeps the tty stream free of color codes so assertions can match on `>` and text only. Cursor and line escapes are still emitted.

**Step 2: Write a harness self-test**

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "pty: snippet sees a tty on stdin and /dev/tty" {
    tuin_pty '' -- '[[ -t 0 && -r /dev/tty ]] && echo yes'
    [ "$pty_status" = 0 ]
    [ "$pty_out" = yes ]
}

@test "pty: keys reach the snippet" {
    tuin_pty 'hello\r' -- 'IFS= read -r line; printf "%s" "$line"'
    [ "$pty_out" = hello ]
}

@test "pty: non-zero status is captured" {
    tuin_pty '' -- 'exit 7'
    [ "$pty_status" = 7 ]
}

@test "pty: existing tuin_choose picks with arrow + enter" {
    tuin_pty '\033[B\r' -- 'tuin_choose alpha bravo charlie'
    [ "$pty_status" = 0 ]
    [ "$pty_out" = bravo ]
}
```

**Step 3: Run**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_pty_harness.bats`
Expected: 4 tests pass.

**Step 4: Commit**

```bash
git add tests/test_helper/pty.bash tests/test_pty_harness.bats
git commit -m "test: add script(1)-based PTY harness"
```

---

### Task 2: CI runs bash 3.2 for real on macOS

**Files:**
- Modify: `.github/workflows/ci.yml`

**Step 1: Pin the system bash on macOS and assert its version**

Replace the `test` job steps with:

```yaml
      - uses: actions/checkout@v5
        with:
          submodules: recursive
      - name: use system bash on macOS
        if: runner.os == 'macOS'
        run: echo "/bin" >> "$GITHUB_PATH"
      - name: bash version
        run: |
          bash --version | head -1
          if [ "${{ runner.os }}" = macOS ]; then
            bash --version | head -1 | grep -q 'version 3\.2' || { echo "expected bash 3.2 on macOS"; exit 1; }
          fi
      - name: run BATS
        run: tests/test_helper/bats-core/bin/bats tests/
```

`$GITHUB_PATH` prepends, so `/bin/bash` (3.2) shadows Homebrew's bash 5 for every later step.

**Step 2: Verify locally the same way**

Run: `PATH=/bin:/usr/bin:$PATH bash --version | head -1`
Expected: `GNU bash, version 3.2.57...`

Run: `PATH=/bin:/usr/bin:$PATH make test`
Expected: all green.

**Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run the macOS suite under the system bash 3.2 and assert it"
```

---

### Task 3: `_tuin_readkey`

**Files:**
- Modify: `tuin.sh` (add after the color block, before `tuin_version`)
- Create: `tests/test_readkey.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$TUIN_SH"
}

# Feed raw bytes on fd 3 and print the token.
key() {
    _tuin_readkey 3< <(printf "$1") && printf '%s' "$_tuin_key"
}

@test "readkey: enter on CR and LF" {
    [ "$(key '\r')" = enter ]
    [ "$(key '\n')" = enter ]
}

@test "readkey: bare ESC" {
    [ "$(key '\033')" = esc ]
}

@test "readkey: CSI arrows" {
    [ "$(key '\033[A')" = up ]
    [ "$(key '\033[B')" = down ]
    [ "$(key '\033[C')" = right ]
    [ "$(key '\033[D')" = left ]
}

@test "readkey: SS3 arrows (application mode)" {
    [ "$(key '\033OA')" = up ]
    [ "$(key '\033OD')" = left ]
}

@test "readkey: home/end in all common encodings" {
    [ "$(key '\033[H')" = home ]
    [ "$(key '\033[F')" = end ]
    [ "$(key '\033[1~')" = home ]
    [ "$(key '\033[4~')" = end ]
    [ "$(key '\033[7~')" = home ]
    [ "$(key '\033[8~')" = end ]
    [ "$(key '\033OH')" = home ]
    [ "$(key '\033OF')" = end ]
}

@test "readkey: page keys, shift-tab" {
    [ "$(key '\033[5~')" = pgup ]
    [ "$(key '\033[6~')" = pgdn ]
    [ "$(key '\033[Z')" = shift-tab ]
}

@test "readkey: unknown CSI is consumed whole, not leaked" {
    # F5 is ESC[15~ ; must yield one 'unknown', then EOF (return 1)
    _tuin_readkey 3< <(printf '\033[15~')
    [ "$_tuin_key" = unknown ]
    run bash -c "source '$TUIN_SH'; { _tuin_readkey; _tuin_readkey; echo rc=\$?; } 3< <(printf '\033[15~')"
    [[ "$output" == *"rc=1"* ]]
}

@test "readkey: alt chords" {
    [ "$(key '\033x')" = alt-x ]
}

@test "readkey: backspace, tab, control letters" {
    [ "$(key '\177')" = bs ]
    [ "$(key '\b')" = bs ]
    [ "$(key '\t')" = tab ]
    [ "$(key '\001')" = ctrl-a ]
    [ "$(key '\016')" = ctrl-n ]
    [ "$(key '\020')" = ctrl-p ]
    [ "$(key '\025')" = ctrl-u ]
    [ "$(key '\027')" = ctrl-w ]
}

@test "readkey: printable chars, including space and digits" {
    [ "$(key 'j')" = char:j ]
    [ "$(key '3')" = char:3 ]
    [ "$(key ' ')" = 'char: ' ]
}

@test "readkey: multi-byte UTF-8 arrives as one char" {
    LC_ALL=en_US.UTF-8 run bash -c "source '$TUIN_SH'; _tuin_readkey 3< <(printf '\303\251') && printf '%s' \"\$_tuin_key\""
    [ "$output" = 'char:é' ]
}

@test "readkey: EOF returns 1" {
    run bash -c "source '$TUIN_SH'; _tuin_readkey 3< /dev/null; echo rc=\$?"
    [ "$output" = rc=1 ]
}

@test "readkey: ESC delay is probed at source time" {
    [[ "$_TUIN_ESC_DELAY" == 1 || "$_TUIN_ESC_DELAY" == 0.05 ]]
}

@test "readkey: TUIN_ESC_DELAY overrides the probe" {
    TUIN_ESC_DELAY=2 run bash -c "source '$TUIN_SH'; echo \$_TUIN_ESC_DELAY"
    [ "$output" = 2 ]
}
```

**Step 2: Run to verify failure**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_readkey.bats`
Expected: FAIL, `_tuin_readkey: command not found`.

**Step 3: Implement**

Insert into `tuin.sh` after the color block and its `fi`:

```bash
# ---------------------------------------------------------------------------
# Key input (private)
# ---------------------------------------------------------------------------

# Bare ESC must be told apart from an escape sequence by waiting briefly for
# more bytes. bash 4+ accepts a fractional read -t; bash 3.2 only integers.
_tuin_detect_esc_delay() {
    local REPLY
    if read -t 0.05 <<< '' 2>/dev/null; then
        printf '0.05\n'
    else
        printf '1\n'
    fi
}
_TUIN_ESC_DELAY="${TUIN_ESC_DELAY:-$(_tuin_detect_esc_delay)}"

# Byte length of $1 regardless of locale.
_tuin_bytelen() {
    local LC_ALL=C
    printf '%d\n' "${#1}"
}

# Signed-safe ordinal of the first byte of $1.
_tuin_ord() {
    local LC_ALL=C n
    n=$(printf '%d' "'$1")
    (( n < 0 )) && n=$((n + 256))
    printf '%d\n' "$n"
}

# Read one keystroke from fd 3 into $_tuin_key as a normalized token:
#   enter esc up down left right home end pgup pgdn tab shift-tab bs
#   ctrl-a..ctrl-z alt-<c> char:<c> unknown
# Returns 1 on EOF. Polls with a 1 s timeout so a signal-triggered trap
# (which bash 3.2's read would otherwise restart through) is noticed by the
# caller via $_TUIN_INTERRUPTED between polls.
_tuin_readkey() {
    local k s c seq n ord rc
    while :; do
        IFS= read -rsn1 -t 1 k <&3
        rc=$?
        (( _TUIN_INTERRUPTED )) && { _tuin_key=interrupt; return 0; }
        (( rc == 0 )) && break
        (( rc > 128 )) && continue
        return 1
    done

    case "$k" in
        ''|$'\r') _tuin_key=enter; return 0 ;;
        $'\t')    _tuin_key=tab;   return 0 ;;
        $'\177'|$'\b') _tuin_key=bs; return 0 ;;
        $'\033')
            if ! IFS= read -rsn1 -t "$_TUIN_ESC_DELAY" s <&3 2>/dev/null; then
                _tuin_key=esc; return 0
            fi
            case "$s" in
                '[')
                    seq=""; n=0
                    while (( n < 8 )); do
                        IFS= read -rsn1 -t "$_TUIN_ESC_DELAY" c <&3 2>/dev/null || break
                        seq="$seq$c"; n=$((n + 1))
                        case "$c" in [0-9\;]) ;; *) break ;; esac
                    done
                    case "$seq" in
                        A) _tuin_key=up ;;    B) _tuin_key=down ;;
                        C) _tuin_key=right ;; D) _tuin_key=left ;;
                        H|1~|7~) _tuin_key=home ;;
                        F|4~|8~) _tuin_key=end ;;
                        5~) _tuin_key=pgup ;;  6~) _tuin_key=pgdn ;;
                        Z)  _tuin_key=shift-tab ;;
                        *)  _tuin_key=unknown ;;
                    esac
                    return 0 ;;
                'O')
                    IFS= read -rsn1 -t "$_TUIN_ESC_DELAY" c <&3 2>/dev/null || c=""
                    case "$c" in
                        A) _tuin_key=up ;;   B) _tuin_key=down ;;
                        C) _tuin_key=right ;; D) _tuin_key=left ;;
                        H) _tuin_key=home ;; F) _tuin_key=end ;;
                        *) _tuin_key=unknown ;;
                    esac
                    return 0 ;;
                *)
                    if [[ "$s" == [[:print:]] ]]; then
                        _tuin_key="alt-$s"
                    else
                        _tuin_key=unknown
                    fi
                    return 0 ;;
            esac ;;
    esac

    # Already a full multi-byte char (bash 4+ under a UTF-8 locale).
    if (( $(_tuin_bytelen "$k") > 1 )); then
        _tuin_key="char:$k"; return 0
    fi

    ord=$(_tuin_ord "$k")
    if (( ord >= 1 && ord <= 26 )); then
        local letters=abcdefghijklmnopqrstuvwxyz
        _tuin_key="ctrl-${letters:$((ord - 1)):1}"; return 0
    fi
    if (( ord >= 194 && ord <= 244 )); then
        # bash 3.2 reads bytes: pull the UTF-8 continuation bytes.
        n=1; (( ord >= 224 )) && n=2; (( ord >= 240 )) && n=3
        IFS= read -rsn"$n" -t "$_TUIN_ESC_DELAY" s <&3 2>/dev/null || s=""
        _tuin_key="char:$k$s"; return 0
    fi
    if (( ord >= 32 && ord <= 126 )); then
        _tuin_key="char:$k"; return 0
    fi
    _tuin_key=unknown
    return 0
}
```

Also add, next to the other source-time globals (right after `_TUIN_VERSION="0.1.0"`):

```bash
# Interactive-state globals. Initialized here so `set -u` callers are safe.
_TUIN_INTERRUPTED=0
_TUIN_REDRAW=0
_TUIN_TTY_ACTIVE=0
_TUIN_OWN_EXIT=0
_TUIN_STTY_SAVED=""
_TUIN_MENU_LAST_TITLE=""
_TUIN_MENU_LAST_INDEX=0
_tuin_key=""
```

**Step 4: Run tests**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_readkey.bats`
Expected: all pass. If the UTF-8 test fails because `en_US.UTF-8` is missing, use `C.UTF-8` on Linux; the test should try `en_US.UTF-8` then `C.UTF-8` via `locale -a`. Keep whichever exists.

Run: `make lint` and `PATH=/bin:/usr/bin:$PATH make test`
Expected: green.

**Step 5: Commit**

```bash
git add tuin.sh tests/test_readkey.bats
git commit -m "feat: add _tuin_readkey, a normalized keystroke reader"
```

---

### Task 4: tty lifecycle helpers

**Files:**
- Modify: `tuin.sh` (after `_tuin_readkey`)
- Create: `tests/test_tty.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "tty: enter/leave restore stty exactly" {
    tuin_pty '' -- '
        before=$(stty -g)
        _tuin_tty_enter
        during=$(stty -g <&3)
        _tuin_tty_leave
        after=$(stty -g)
        [[ "$before" == "$after" && "$before" != "$during" ]] && echo ok'
    [ "$pty_out" = ok ]
}

@test "tty: leave shows the cursor and closes fd 3" {
    tuin_pty '' -- '
        _tuin_tty_enter; _tuin_tty_leave
        { : <&3; } 2>/dev/null && echo "fd3 open" || echo closed'
    [ "$pty_out" = closed ]
    [[ "$pty_tty" == *$'\033[?25l'*$'\033[?25h'* ]]
}

@test "tty: leave is idempotent" {
    tuin_pty '' -- '_tuin_tty_enter; _tuin_tty_leave; _tuin_tty_leave; echo ok'
    [ "$pty_out" = ok ]
}

@test "tty: enter fails cleanly without a terminal" {
    run bash -c "source '$TUIN_SH'; _tuin_tty_enter </dev/null >/dev/null 2>&1; echo rc=\$?"
    [[ "$output" == rc=[1-9]* ]] || [ "$output" = rc=0 ]
    # Either outcome acceptable: some CI sandboxes expose a /dev/tty. What
    # matters is no crash and no stray output; asserted by run succeeding.
}

@test "tty: signals are reset to default after leave" {
    tuin_pty '' -- '_tuin_tty_enter; _tuin_tty_leave; trap -p INT TERM TSTP CONT WINCH EXIT | wc -l'
    [ "$(printf '%s' "$pty_out" | tr -d ' ')" = 0 ]
}

@test "tty: a caller EXIT trap is left alone" {
    tuin_pty '' -- 'trap "echo caller-exit" EXIT; _tuin_tty_enter; _tuin_tty_leave; trap -p EXIT'
    [[ "$pty_out" == *caller-exit* ]]
}

@test "tty: Ctrl-C inside a primitive restores the terminal and returns 130" {
    tuin_pty '\003' -- 'before=$(stty -g); tuin_choose a b c; rc=$?; after=$(stty -g); [[ "$before" == "$after" ]] && echo "rc=$rc"'
    [ "$pty_out" = rc=130 ]
}

@test "tty: suspend restores cooked mode, resume re-enters raw and flags redraw" {
    tuin_pty '' -- '
        kill() { :; }   # stub: do not actually stop
        before=$(stty -g)
        _tuin_tty_enter
        _tuin_tty_suspend
        parked=$(stty -g <&3)
        _tuin_tty_resume
        resumed=$(stty -g <&3)
        _tuin_tty_leave
        [[ "$parked" == "$before" && "$resumed" != "$before" && $_TUIN_REDRAW == 1 ]] && echo ok'
    [ "$pty_out" = ok ]
}
```

**Step 2: Run to verify failure**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_tty.bats`
Expected: FAIL, `_tuin_tty_enter: command not found`.

**Step 3: Implement**

```bash
# ---------------------------------------------------------------------------
# Terminal lifecycle (private)
# ---------------------------------------------------------------------------
# _tuin_tty_enter opens fd 3 on /dev/tty, saves stty, enters raw-ish mode,
# hides the cursor, and installs tuin's signal traps. _tuin_tty_leave undoes
# all of it and is safe to call more than once. While a primitive is active,
# tuin owns INT TERM TSTP CONT WINCH (reset to default on leave) and EXIT
# only if the caller had no EXIT trap of its own.

_tuin_tty_raw() {
    stty -icanon -echo min 1 time 0 <&3 2>/dev/null
    printf '\033[?25l' >&3
}

_tuin_tty_cooked() {
    printf '\033[?25h' >&3
    stty "$_TUIN_STTY_SAVED" <&3 2>/dev/null
}

_tuin_tty_enter() {
    (( _TUIN_TTY_ACTIVE )) && return 0
    exec 3<>/dev/tty 2>/dev/null || return 1
    _TUIN_STTY_SAVED=$(stty -g <&3 2>/dev/null) || { exec 3<&-; return 1; }
    _TUIN_TTY_ACTIVE=1
    _TUIN_INTERRUPTED=0
    _TUIN_REDRAW=0
    _tuin_tty_raw
    trap '_TUIN_INTERRUPTED=1; _tuin_tty_leave' INT TERM
    trap '_tuin_tty_suspend' TSTP
    trap '_tuin_tty_resume' CONT
    trap '_TUIN_REDRAW=1' WINCH
    if [[ -z "$(trap -p EXIT)" ]]; then
        _TUIN_OWN_EXIT=1
        trap '_tuin_tty_leave' EXIT
    fi
    return 0
}

_tuin_tty_leave() {
    (( _TUIN_TTY_ACTIVE )) || return 0
    _tuin_tty_cooked
    exec 3<&-
    _TUIN_TTY_ACTIVE=0
    trap - INT TERM TSTP CONT WINCH
    if (( _TUIN_OWN_EXIT )); then
        trap - EXIT
        _TUIN_OWN_EXIT=0
    fi
    return 0
}

# Ctrl-Z: hand the terminal back in cooked mode, stop ourselves for real,
# and re-enter raw mode from the CONT trap when the shell fg's us.
_tuin_tty_suspend() {
    _tuin_tty_cooked
    trap - TSTP
    kill -TSTP $$
}

_tuin_tty_resume() {
    (( _TUIN_TTY_ACTIVE )) || return 0
    _tuin_tty_raw
    trap '_tuin_tty_suspend' TSTP
    _TUIN_REDRAW=1
}

# Terminal height via the tty itself; falls back to 24.
_tuin_tty_rows() {
    local r c
    read -r r c < <(stty size <&3 2>/dev/null)
    [[ "$r" =~ ^[0-9]+$ ]] && (( r > 0 )) || r=24
    printf '%d\n' "$r"
}
```

**Step 4: Run tests**

The Ctrl-C test depends on `tuin_choose` using the new helpers, which is Task 5. Expect that single test to fail here and pass after Task 5. Everything else must pass.

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_tty.bats`

**Step 5: Commit**

```bash
git add tuin.sh tests/test_tty.bats
git commit -m "feat: add tty lifecycle helpers (raw mode, cursor, signal traps)"
```

---

### Task 5: Rebuild `tuin_choose`

**Files:**
- Modify: `tuin.sh` — replace `tuin_choose`, `_tuin_choose_apply_filter`, `_tuin_choose_render`; keep `_tuin_choose_interactive` and `_tuin_choose_filter` as they are.
- Modify: `tests/test_choose.bats` — append PTY tests.

**Step 1: Write the failing tests** (append to `tests/test_choose.bats`; add `load 'test_helper/pty'` to its `setup`)

```bash
# --- interactive (PTY) ------------------------------------------------------

@test "choose: enter picks first" {
    tuin_pty '\r' -- 'tuin_choose alpha bravo charlie'
    [ "$pty_out" = alpha ]
}

@test "choose: arrows, j/k, ctrl-n/p, tab all move" {
    tuin_pty '\033[B\r'  -- 'tuin_choose a b c'; [ "$pty_out" = b ]
    tuin_pty 'j\r'       -- 'tuin_choose a b c'; [ "$pty_out" = b ]
    tuin_pty 'jjk\r'     -- 'tuin_choose a b c'; [ "$pty_out" = b ]
    tuin_pty '\016\r'    -- 'tuin_choose a b c'; [ "$pty_out" = b ]
    tuin_pty '\016\020\r' -- 'tuin_choose a b c'; [ "$pty_out" = a ]
    tuin_pty '\t\t\r'    -- 'tuin_choose a b c'; [ "$pty_out" = c ]
    tuin_pty '\t\033[Z\r' -- 'tuin_choose a b c'; [ "$pty_out" = a ]
}

@test "choose: wraps at both ends" {
    tuin_pty 'k\r'   -- 'tuin_choose a b c'; [ "$pty_out" = c ]
    tuin_pty 'jjj\r' -- 'tuin_choose a b c'; [ "$pty_out" = a ]
}

@test "choose: home/end and g/G" {
    tuin_pty 'G\r'        -- 'tuin_choose a b c'; [ "$pty_out" = c ]
    tuin_pty 'Gg\r'       -- 'tuin_choose a b c'; [ "$pty_out" = a ]
    tuin_pty '\033[F\r'   -- 'tuin_choose a b c'; [ "$pty_out" = c ]
    tuin_pty '\033[F\033[H\r' -- 'tuin_choose a b c'; [ "$pty_out" = a ]
}

@test "choose: digit picks instantly under 10 items and rows are numbered" {
    tuin_pty '2' -- 'tuin_choose alpha bravo charlie'
    [ "$pty_out" = bravo ]
    [[ "$pty_tty" == *"2) bravo"* ]]
}

@test "choose: out-of-range digit is ignored" {
    tuin_pty '9\r' -- 'tuin_choose alpha bravo'
    [ "$pty_out" = alpha ]
}

@test "choose: esc, q, left, backspace cancel with rc 1" {
    for k in '\033' 'q' '\033[D' '\177'; do
        tuin_pty "$k" -- 'tuin_choose a b c; echo "rc=$?"'
        [ "$pty_out" = rc=1 ]
    done
}

@test "choose: 10+ items enter filter mode; typing narrows; enter picks" {
    tuin_pty 'char\r' -- 'tuin_choose alpha bravo charlie d e f g h i j k'
    [ "$pty_out" = charlie ]
    [[ "$pty_tty" == *"filter: char  (1/11)"* ]]
}

@test "choose: in filter mode j/k/q/digits are text, ctrl-n still moves" {
    tuin_pty 'j\r' -- 'tuin_choose jam a b c d e f g h i j; echo "rc=$?"'
    [ "$pty_out" = $'jam\nrc=0' ]
    tuin_pty '\016\r' -- 'tuin_choose a b c d e f g h i j k'
    [ "$pty_out" = b ]
}

@test "choose: filter editing keys" {
    tuin_pty 'xx\177\177b\r' -- 'tuin_choose a b c d e f g h i j k'
    [ "$pty_out" = b ]
    tuin_pty 'zzz\025c\r' -- 'tuin_choose a b c d e f g h i j k'
    [ "$pty_out" = c ]
    tuin_pty 'foo bar\027\027c\r' -- 'tuin_choose a b c d e f g h i j k'
    [ "$pty_out" = c ]
}

@test "choose: esc clears a non-empty filter first, then cancels" {
    tuin_pty 'zzz\033\r' -- 'tuin_choose a b c d e f g h i j k; echo "rc=$?"'
    [ "$pty_out" = $'a\nrc=0' ]
}

@test "choose: enter on an empty filter result returns 1" {
    tuin_pty 'zzz\r' -- 'tuin_choose a b c d e f g h i j k; echo "rc=$?"'
    [ "$pty_out" = rc=1 ]
}

@test "choose: TUIN_FILTER forces filter mode on or off" {
    TUIN_FILTER=1 tuin_pty 'c\r' -- 'tuin_choose alpha bravo charlie'
    [ "$pty_out" = charlie ]
    TUIN_FILTER=0 tuin_pty 'j\r' -- 'tuin_choose a b c d e f g h i j k'
    [ "$pty_out" = b ]
}

@test "choose: labels with control bytes render stripped but return byte-exact" {
    tuin_pty '\r' -- "tuin_choose \$'ev\\033[2Jil' safe"
    [ "$pty_out" = $'ev\033[2Jil' ]
    [[ "$pty_tty" != *$'\033[2J'* ]]
    [[ "$pty_tty" == *"evil"* ]]
}

@test "choose: hint line is shown and TUIN_HINTS=0 hides it" {
    tuin_pty '\r' -- 'tuin_choose a b'
    [[ "$pty_tty" == *"enter pick"* ]]
    TUIN_HINTS=0 tuin_pty '\r' -- 'tuin_choose a b'
    [[ "$pty_tty" != *"enter pick"* ]]
}

@test "choose: shell-escape keys do nothing" {
    tuin_pty '!:\r' -- 'tuin_choose a b c'
    [ "$pty_out" = a ]
}

@test "choose: stty is restored after a normal pick" {
    tuin_pty 'j\r' -- 'b=$(stty -g); tuin_choose a b >/dev/null; [[ "$b" == "$(stty -g)" ]] && echo ok'
    [ "$pty_out" = ok ]
}
```

The `TUIN_FILTER=1 tuin_pty …` form works because `tuin_pty` runs the wrapper as a child that inherits the environment.

**Step 2: Run to verify failure**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_choose.bats`
Expected: the new tests fail (j/k, digits, wrap, hints, etc.). The existing non-TTY tests still pass.

**Step 3: Implement**

Add `_TUIN_DIM` to the color block (both branches; `tput dim` with `\033[2m` fallback) and an empty default above it.

Replace `tuin_choose`, `_tuin_choose_apply_filter`, and `_tuin_choose_render`:

```bash
# tuin_choose <opt1> [opt2 ...]
#
# Interactive: arrow-key list on /dev/tty, value on stdout. Keys:
#   move    up/down, j/k, ctrl-n/ctrl-p, tab/shift-tab, home/end, g/G, pgup/pgdn
#   pick    enter; a digit 1-9 picks instantly when the list has < 10 items
#   cancel  esc, q, left, backspace              (return 1)
#   filter  when >= 10 items or TUIN_FILTER=1: printable keys type,
#           backspace/ctrl-u/ctrl-w edit, esc clears then cancels
# Non-TTY: reads a 1-based index from stdin; falls back to the first option.
# TUIN_HINTS=0 hides the key hint line. Labels are rendered with control
# bytes stripped; the returned value is always the original string.
tuin_choose() {
    if [[ "$#" -eq 0 ]]; then
        return 2
    fi
    local options=("$@")
    local count="${#options[@]}"

    if ! _tuin_choose_interactive || ! _tuin_tty_enter; then
        local pick
        IFS= read -r pick || pick=""
        if [[ "$pick" =~ ^[1-9][0-9]*$ ]] && [[ "$pick" -le "$count" ]]; then
            printf '%s\n' "${options[$((pick - 1))]}"
        else
            printf '%s\n' "${options[0]}"
        fi
        return 0
    fi

    local filter="" filter_enabled=0 numbered=0 hints=1
    case "${TUIN_FILTER:-}" in
        1) filter_enabled=1 ;;
        0) filter_enabled=0 ;;
        *) (( count >= 10 )) && filter_enabled=1 ;;
    esac
    (( ! filter_enabled && count < 10 )) && numbered=1
    [[ "${TUIN_HINTS:-1}" == 0 ]] && hints=0

    local selected=0 top=0 rows=0 max_rows=0 last_height=0
    local filtered_indices=() visible_count i
    for (( i=0; i<count; i++ )); do
        filtered_indices+=("$i")
    done
    visible_count=$count
    if [[ "${_TUIN_CHOOSE_START:-}" =~ ^[0-9]+$ ]] && (( _TUIN_CHOOSE_START < count )); then
        selected=$_TUIN_CHOOSE_START
    fi

    local hint
    if _tuin_is_utf8; then
        hint='↑↓/jk move · enter pick · esc cancel'
    else
        hint='up/down/jk move, enter pick, esc cancel'
    fi
    (( filter_enabled )) && hint="${hint/\/jk/} · type to filter"
    (( numbered )) && hint="${hint/enter pick/1-9 or enter pick}"

    _tuin_choose_draw

    local c
    while :; do
        if ! _tuin_readkey; then
            _tuin_tty_leave
            return 1
        fi
        if (( _TUIN_INTERRUPTED )); then
            _tuin_tty_leave
            return 130
        fi
        case "$_tuin_key" in
            up|ctrl-p|shift-tab) _tuin_choose_move -1 1 ;;
            down|ctrl-n|tab)     _tuin_choose_move 1 1 ;;
            home) selected=0 ;;
            end)  selected=$((visible_count - 1)) ;;
            pgup) _tuin_choose_move "-$rows" 0 ;;
            pgdn) _tuin_choose_move "$rows" 0 ;;
            enter)
                _tuin_tty_leave
                (( visible_count == 0 )) && return 1
                printf '%s\n' "${options[${filtered_indices[$selected]}]}"
                return 0 ;;
            esc)
                if (( filter_enabled )) && [[ -n "$filter" ]]; then
                    filter=""; _tuin_choose_apply_filter
                else
                    _tuin_tty_leave; return 1
                fi ;;
            left) _tuin_tty_leave; return 1 ;;
            bs)
                if (( filter_enabled )) && [[ -n "$filter" ]]; then
                    filter="${filter%?}"; _tuin_choose_apply_filter
                else
                    _tuin_tty_leave; return 1
                fi ;;
            ctrl-u)
                (( filter_enabled )) && { filter=""; _tuin_choose_apply_filter; } ;;
            ctrl-w)
                if (( filter_enabled )); then
                    while [[ "$filter" == *' ' ]]; do filter="${filter% }"; done
                    if [[ "$filter" == *' '* ]]; then
                        filter="${filter% *} "
                    else
                        filter=""
                    fi
                    _tuin_choose_apply_filter
                fi ;;
            char:*)
                c="${_tuin_key#char:}"
                if (( filter_enabled )); then
                    filter="$filter$c"; _tuin_choose_apply_filter
                elif (( numbered )) && [[ "$c" == [1-9] ]] && (( c <= count )); then
                    _tuin_tty_leave
                    printf '%s\n' "${options[$((c - 1))]}"
                    return 0
                else
                    case "$c" in
                        j) _tuin_choose_move 1 1 ;;
                        k) _tuin_choose_move -1 1 ;;
                        g) selected=0 ;;
                        G) selected=$((visible_count - 1)) ;;
                        q) _tuin_tty_leave; return 1 ;;
                    esac
                fi ;;
        esac
        (( selected < 0 )) && selected=0
        _tuin_choose_draw
    done
}

# Helpers below use bash's dynamic scoping to read/write tuin_choose's locals
# (options, count, filter, filter_enabled, numbered, hints, hint, selected,
# top, rows, max_rows, last_height, filtered_indices, visible_count). They are
# module-level so a first tuin_choose call does not install functions into
# the caller's environment, and so tests can call _tuin_choose_filter alone.

# _tuin_choose_move <delta> <wrap:0|1>
_tuin_choose_move() {
    local delta=$1 wrap=$2
    (( visible_count == 0 )) && { selected=0; return 0; }
    selected=$((selected + delta))
    if (( wrap )); then
        (( selected < 0 )) && selected=$((visible_count - 1))
        (( selected >= visible_count )) && selected=0
    else
        (( selected < 0 )) && selected=0
        (( selected >= visible_count )) && selected=$((visible_count - 1))
    fi
}

_tuin_choose_apply_filter() {
    filtered_indices=()
    if [[ -z "$filter" ]]; then
        local j
        for (( j=0; j<count; j++ )); do
            filtered_indices+=("$j")
        done
    else
        local line
        while IFS= read -r line; do
            filtered_indices+=("$line")
        done < <(_tuin_choose_filter "$filter" "${options[@]}")
    fi
    visible_count="${#filtered_indices[@]}"
    if (( visible_count == 0 )); then
        selected=0
    elif (( selected >= visible_count )); then
        selected=$((visible_count - 1))
    fi
}

# Clamp the viewport to the terminal, move the cursor back over the previous
# frame, render, and blank any rows the previous frame used that this one
# does not.
_tuin_choose_draw() {
    if (( max_rows == 0 || _TUIN_REDRAW )); then
        max_rows=$(( $(_tuin_tty_rows) - 3 ))
        (( max_rows < 1 )) && max_rows=1
        _TUIN_REDRAW=0
    fi
    rows=$visible_count
    (( rows > max_rows )) && rows=$max_rows
    (( selected < top )) && top=$selected
    (( selected >= top + rows )) && top=$((selected - rows + 1))
    (( top + rows > visible_count )) && top=$((visible_count - rows))
    (( top < 0 )) && top=0

    local height=$((rows + filter_enabled + hints))
    (( last_height > 0 )) && printf '\033[%dA' "$last_height" >&3
    _tuin_choose_render >&3
    if (( height < last_height )); then
        local extras=$((last_height - height)) x
        for (( x=0; x<extras; x++ )); do
            printf '\r\033[K\n' >&3
        done
        printf '\033[%dA' "$extras" >&3
    fi
    last_height=$height
}

_tuin_choose_render() {
    local pos idx label prefix
    for (( pos=top; pos<top+rows; pos++ )); do
        idx="${filtered_indices[$pos]}"
        label="${options[$idx]//[[:cntrl:]]/}"
        prefix=""
        (( numbered )) && prefix="$((idx + 1))) "
        printf '\r\033[K'
        if (( pos == selected )); then
            printf '%s>%s %s%s%s%s\n' \
                "$_TUIN_CYAN" "$_TUIN_RESET" \
                "$_TUIN_REV" "$prefix" "$label" "$_TUIN_RESET"
        else
            printf '  %s%s\n' "$prefix" "$label"
        fi
    done
    if (( filter_enabled )); then
        printf '\r\033[K  filter: %s  (%d/%d)\n' "${filter//[[:cntrl:]]/}" "$visible_count" "$count"
    fi
    if (( hints )); then
        printf '\r\033[K%s%s%s\n' "$_TUIN_DIM" "$hint" "$_TUIN_RESET"
    fi
}
```

Delete the "Known v0.1.0 limitation" block from the file header; the polling reader makes it untrue.

**Step 4: Run tests**

Run: `PATH=/bin:/usr/bin:$PATH make test && make lint`
Expected: green, including the Ctrl-C test from Task 4. If the hint-line assertion fails because the tty stream wraps, widen the match to `"enter pick"` only, as written.

**Step 5: Commit**

```bash
git add tuin.sh tests/test_choose.bats
git commit -m "feat(choose): vi/emacs navigation, digit hotkeys, wrap, viewport, filter editing, label sanitizing"
```

---

### Task 6: Viewport and resize test

**Files:**
- Modify: `tests/test_choose.bats`

The viewport code landed in Task 5; this task proves it.

**Step 1: Write the tests**

```bash
@test "choose: long list is clipped to the terminal height and scrolls" {
    # 40 items, terminal forced to 10 rows via stty
    tuin_pty 'G\r' -- 'stty rows 10; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 40 ]
    # never more than 7 item rows in one frame (10 - 3)
    [[ "$pty_tty" != *"  33"*"  39"*"  40"* ]] || true
    [[ "$pty_tty" == *"> 40"* ]]
}

@test "choose: pgdn/pgup move by a page" {
    tuin_pty 'stty rows 10\r' -- 'true'   # no-op warm-up so the harness is exercised
    tuin_pty '\033[6~\r' -- 'stty rows 10; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 8 ]
    tuin_pty '\033[6~\033[6~\033[5~\r' -- 'stty rows 10; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 8 ]
}

@test "choose: WINCH triggers a redraw with the new height" {
    tuin_pty '' -- '
        stty rows 10
        ( sleep 0.6; stty rows 30 </dev/tty; kill -WINCH $$ ; sleep 0.3; printf "\r" > /dev/tty ) &
        tuin_choose $(seq 1 40)'
    [ "$pty_out" = 1 ]
    # after resize, a frame shows more than 7 rows: item 20 appears
    [[ "$pty_tty" == *"  20"* ]]
}
```

Adjust the exact expected values after observing a run; the point is that pgdn moves by `rows`, which is 7 for a 10-line terminal (index 7 is item 8).

**Step 2: Run, adjust, commit**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_choose.bats`

```bash
git add tests/test_choose.bats
git commit -m "test(choose): viewport clipping, paging, and WINCH redraw"
```

---

### Task 7: `tuin_menu` cursor memory and Back keys

**Files:**
- Modify: `tuin.sh` — `tuin_menu` interactive branch
- Modify: `tests/test_menu.bats` — append PTY tests

**Step 1: Write the failing tests** (add `load 'test_helper/pty'` to setup)

```bash
@test "menu: q, left, backspace all mean Back" {
    for k in 'q' '\033[D' '\177' '\033'; do
        tuin_pty "$k" -- 'tuin_menu Title A B; echo "rc=$?"'
        [ "$pty_out" = rc=1 ]
    done
}

@test "menu: cursor is remembered across loop iterations" {
    tuin_pty 'j\r\r\033' -- '
        n=0
        while tuin_menu Title A B C; do n=$((n+1)); echo "$n:$TUIN_REPLY"; done'
    [ "$pty_out" = $'1:B\n2:B' ]
}

@test "menu: a different title starts at the top" {
    tuin_pty 'j\r\r\033' -- '
        tuin_menu One A B C; echo "$TUIN_REPLY"
        tuin_menu Two A B C; echo "$TUIN_REPLY"'
    [ "$pty_out" = $'B\nA' ]
}

@test "menu: no _TUIN_CHOOSE_START leaks to the caller" {
    tuin_pty '\r\033' -- 'tuin_menu T A; echo "[${_TUIN_CHOOSE_START:-unset}]"'
    [ "$pty_out" = '[unset]' ]
}
```

**Step 2: Run to verify failure**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_menu.bats`
Expected: cursor-memory tests fail.

**Step 3: Implement**

Replace the interactive branch of `tuin_menu`:

```bash
    if _tuin_choose_interactive; then
        printf '%s\n' "$title" >/dev/tty 2>/dev/null
        local sel rc start=0 i
        [[ "$title" == "$_TUIN_MENU_LAST_TITLE" ]] && start=$_TUIN_MENU_LAST_INDEX
        _TUIN_CHOOSE_START=$start
        sel=$(tuin_choose "${opts[@]}"); rc=$?
        unset _TUIN_CHOOSE_START
        (( rc != 0 )) && return 1
        [[ "$sel" == "$back" ]] && return 1
        _TUIN_MENU_LAST_TITLE="$title"
        for (( i=0; i<${#opts[@]}; i++ )); do
            [[ "${opts[$i]}" == "$sel" ]] && { _TUIN_MENU_LAST_INDEX=$i; break; }
        done
        TUIN_REPLY="$sel"
        return 0
    fi
```

Update the comment above `tuin_menu` to mention the Back keys and the cursor memory.

**Step 4: Run tests, lint, commit**

```bash
git add tuin.sh tests/test_menu.bats
git commit -m "feat(menu): remember cursor across iterations; q/left/backspace go Back"
```

---

### Task 8: `tuin_confirm` on the key reader

**Files:**
- Modify: `tuin.sh` — `tuin_confirm` interactive branch
- Modify: `tests/test_confirm.bats` — append PTY tests

**Step 1: Write the failing tests** (add `load 'test_helper/pty'` to setup)

```bash
@test "confirm: y/n single keypress" {
    tuin_pty 'y' -- 'tuin_confirm "Go?"; echo "rc=$?"'; [ "$pty_out" = rc=0 ]
    tuin_pty 'n' -- 'tuin_confirm "Go?"; echo "rc=$?"'; [ "$pty_out" = rc=1 ]
}

@test "confirm: enter takes the default" {
    tuin_pty '\r' -- 'tuin_confirm "Go?" y; echo "rc=$?"'; [ "$pty_out" = rc=0 ]
    tuin_pty '\r' -- 'tuin_confirm "Go?" n; echo "rc=$?"'; [ "$pty_out" = rc=1 ]
}

@test "confirm: esc and q are no" {
    tuin_pty '\033' -- 'tuin_confirm "Go?" y; echo "rc=$?"'; [ "$pty_out" = rc=1 ]
    tuin_pty 'q'    -- 'tuin_confirm "Go?" y; echo "rc=$?"'; [ "$pty_out" = rc=1 ]
}

@test "confirm: Ctrl-C returns 130 with the tty restored" {
    tuin_pty '\003' -- 'b=$(stty -g); tuin_confirm "Go?"; rc=$?; [[ "$b" == "$(stty -g)" ]] && echo "rc=$rc"'
    [ "$pty_out" = rc=130 ]
}

@test "confirm: prompt shows the default indicator" {
    tuin_pty 'y' -- 'tuin_confirm "Go?" y'
    [[ "$pty_tty" == *"Go? [Y/n]"* ]]
}
```

**Step 2: Run to verify failure** (esc/q/Ctrl-C tests fail)

**Step 3: Implement**

Replace the interactive tail of `tuin_confirm` (everything after the non-TTY block):

```bash
    printf '%s %s ' "$prompt" "$indicator"
    if ! _tuin_tty_enter; then
        # No /dev/tty: behave like v0.1 and read a single key from stdin.
        IFS= read -rsn1 key
        printf '\n'
        case "$key" in
            y|Y) return 0 ;;
            ""|$'\n') [[ "$default" == [yY] ]] && return 0; return 1 ;;
            *) return 1 ;;
        esac
    fi
    local _tuin_key rc=1
    while :; do
        if ! _tuin_readkey; then rc=1; break; fi
        if (( _TUIN_INTERRUPTED )); then rc=130; break; fi
        case "$_tuin_key" in
            char:y|char:Y) rc=0; break ;;
            char:n|char:N|char:q|esc) rc=1; break ;;
            enter) [[ "$default" == [yY] ]] && rc=0 || rc=1; break ;;
        esac
    done
    _tuin_tty_leave
    printf '\n'
    return "$rc"
```

Unknown keys are ignored, so a stray arrow no longer counts as "no".

**Step 4: Run tests, lint, commit**

```bash
git add tuin.sh tests/test_confirm.bats
git commit -m "feat(confirm): esc/q mean no, Ctrl-C returns 130, stray keys ignored"
```

---

### Task 9: `tuin_input` with readline and EOF

**Files:**
- Modify: `tuin.sh` — `tuin_input` interactive loop
- Modify: `tests/test_input.bats` — append PTY tests

**Step 1: Write the failing tests** (add `load 'test_helper/pty'` to setup)

```bash
@test "input: readline editing works (ctrl-a, ctrl-e, ctrl-w)" {
    tuin_pty 'bc\001a\005d\r' -- 'tuin_input Name'
    [ "$pty_out" = abcd ]
    tuin_pty 'foo bar\027baz\r' -- 'tuin_input Name'
    [ "$pty_out" = 'foo baz' ]
}

@test "input: value is capturable while readline echoes to the terminal" {
    tuin_pty 'x\r' -- 'v=$(tuin_input Name); printf "[%s]" "$v"'
    [ "$pty_out" = '[x]' ]
}

@test "input: empty enter takes the default" {
    tuin_pty '\r' -- 'tuin_input Name World'
    [ "$pty_out" = World ]
}

@test "input: regex rejects then accepts" {
    tuin_pty '12\rab\r' -- "tuin_input Letters '' '^[a-z]+\$'"
    [ "$pty_out" = ab ]
    [[ "$pty_tty" == *invalid* ]]
}

@test "input: Ctrl-D returns 1 with empty output, even with a regex" {
    tuin_pty '\004' -- "tuin_input Letters '' '^[a-z]+\$'; echo \"rc=\$?\""
    [ "$pty_out" = rc=1 ]
}
```

**Step 2: Run to verify failure** (readline and Ctrl-D tests fail; Ctrl-D currently loops until the harness tail expires)

**Step 3: Implement**

Replace the `while :; do … done` loop in `tuin_input`:

```bash
    while :; do
        if ! IFS= read -e -r -p "$built_prompt" value; then
            printf '\n' >&2
            return 1
        fi
        [[ -z "$value" ]] && value="$default"
        if [[ -z "$regex" ]] || [[ "$value" =~ $regex ]]; then
            printf '%s\n' "$value"
            return 0
        fi
        printf '  invalid; expected match /%s/\n' "$regex" >&2
    done
```

`read -e` echoes through readline to stderr, so stdout still carries only the value. Ctrl-C is left to the shell's default, as with any `read -p`.

Update the comment and the header line for `tuin_input` to mention readline and the `1` on EOF.

**Step 4: Run tests, lint, commit**

```bash
git add tuin.sh tests/test_input.bats
git commit -m "feat(input): readline editing; return 1 on EOF instead of looping"
```

---

### Task 10: Security guard tests

**Files:**
- Create: `tests/test_security.bats`

**Step 1: Write the tests**

```bash
#!/usr/bin/env bats
# tuin is a UX layer. It must never turn text into a command.

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "security: tuin.sh contains no eval / sh -c / indirect expansion" {
    run grep -nE '(^|[^a-zA-Z_])eval[[:space:]]|[[:space:]](sh|bash|zsh)[[:space:]]+-c[[:space:]]|\$\{![a-zA-Z_]' "$TUIN_SH"
    [ "$status" -ne 0 ] || fail "forbidden construct in tuin.sh:
$output"
}

@test "security: every \$@ / \$* in tuin.sh is quoted" {
    run grep -nE '[^"]\$[@*]([^"]|$)' "$TUIN_SH"
    [ "$status" -ne 0 ] || fail "unquoted \$@ or \$* in tuin.sh:
$output"
}

@test "security: no shell-escape key in any primitive" {
    tuin_pty '!\r'  -- 'tuin_choose a b';        [ "$pty_out" = a ]
    tuin_pty ':\r'  -- 'tuin_choose a b';        [ "$pty_out" = a ]
    tuin_pty '!q'   -- 'tuin_confirm Go?; echo "rc=$?"'; [ "$pty_out" = rc=1 ]
    tuin_pty '!\r\033' -- 'tuin_menu T A; echo "rc=$?"'; [ "$pty_out" = rc=1 ]
}

@test "security: menu labels and titles with escapes never reach the terminal raw" {
    tuin_pty '\r\033' -- "tuin_menu \$'T\\033[2J' \$'A\\007'; printf '%s' \"\$TUIN_REPLY\""
    [ "$pty_out" = $'A\007' ]
    [[ "$pty_tty" != *$'\033[2J'* ]]
    [[ "$pty_tty" != *$'\007'* ]]
}

@test "security: tuin_spin runs argv only, no word splitting" {
    run bash -c "source '$TUIN_SH'; tuin_spin Label -- printf '%s|' 'a b' 'c;d' </dev/null"
    assert_output "a b|c;d|"
}
```

The menu-title test requires `tuin_menu` to strip control bytes from the title it prints. Add `"${title//[[:cntrl:]]/}"` to both `printf` calls of the title in `tuin_menu` and to the non-TTY numbered listing labels.

**Step 2: Run, fix what it catches, commit**

Run: `PATH=/bin:/usr/bin:$PATH tests/test_helper/bats-core/bin/bats tests/test_security.bats`

```bash
git add tuin.sh tests/test_security.bats
git commit -m "test: security guards — no eval, no shell escape, no escape injection"
```

---

### Task 11: Docs, changelog, version bump target

**Files:**
- Modify: `README.md`, `AGENTS.md`, `CHANGELOG.md`, `Makefile`, `tuin.sh` (header), `tests/test_docs.bats`, `tests/test_release.bats`
- Create: `docs/ROADMAP.md`

**Step 1: Write the failing doc tests** (append to `tests/test_docs.bats`)

```bash
@test "README documents every TUIN_* environment variable used in tuin.sh" {
    local var
    while IFS= read -r var; do
        grep -qF "$var" "$TUIN_REPO_ROOT/README.md" \
            || fail "README.md is missing env var: $var"
    done < <(grep -oE '\$\{TUIN_[A-Z_]+' "$TUIN_SH" | tr -d '${' | sort -u)
}

@test "README has a keyboard reference for tuin_choose" {
    grep -qF 'ctrl-n' "$TUIN_REPO_ROOT/README.md"
    grep -qF 'shift-tab' "$TUIN_REPO_ROOT/README.md"
}

@test "docs/ROADMAP.md exists" {
    [ -f "$TUIN_REPO_ROOT/docs/ROADMAP.md" ]
}

@test "tuin.sh header no longer carries the Ctrl-C known limitation" {
    ! grep -q 'Known v0.1.0 limitation' "$TUIN_SH"
}
```

And to `tests/test_release.bats`:

```bash
@test "make bump refuses a dirty tree and rewrites both version locations" {
    tmp=$(mktemp -d)
    git -C "$TUIN_REPO_ROOT" archive HEAD | tar -x -C "$tmp"
    git -C "$tmp" init -q && git -C "$tmp" add -A && git -C "$tmp" -c user.email=t@t -c user.name=t commit -qm init
    run make -C "$tmp" bump V=9.9.9
    assert_success
    run grep -c '9\.9\.9' "$tmp/tuin.sh"
    assert_output 2
    echo x >> "$tmp/README.md"
    run make -C "$tmp" bump V=9.9.10
    assert_failure
}
```

**Step 2: Implement the docs**

README:
- In the `tuin_choose` section add a key table (move, pick, cancel, filter keys) matching the comment block in Task 5, and note digits under 10 items.
- Add an **Environment variables** table: `NO_COLOR`, `TUIN_MENU_BACK`, `TUIN_FILTER` (`1` force on, `0` force off), `TUIN_HINTS` (`0` hides the hint line), `TUIN_ESC_DELAY` (seconds, overrides the probe).
- `tuin_input`: mention readline editing on a TTY, `1` on EOF.
- `tuin_confirm`: esc/q are no, 130 on Ctrl-C.
- `tuin_menu`: q/left/backspace go Back; cursor remembered when the same title loops.
- A short **Signals** paragraph: what tuin traps while a primitive is active, that it resets them afterwards, and that a caller's own EXIT trap is left alone.

AGENTS.md: update the API table return codes for `tuin_input` (`0` ok, `1` EOF), add the env-var list under rules, add one gotcha: "don't put ANSI in labels; tuin strips control bytes when rendering".

CHANGELOG `[Unreleased]`: Added (keys, hotkeys, wrap, viewport, hints, readline, cursor memory, env vars, PTY suite), Changed (`tuin_input` EOF returns 1; control bytes stripped from rendered labels), Fixed (bash 3.2 double Ctrl-C; tty left raw on Ctrl-Z; caller EXIT trap no longer clobbered).

`docs/ROADMAP.md`: the deferred items from the v0.1.0 design doc's deferred list, verbatim, plus "per-title cursor memory in tuin_menu" and "Linux bash 3.2 CI job".

Makefile, add:

```make
bump:
	@test -n "$(V)" || { echo "usage: make bump V=X.Y.Z"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "working tree not clean"; exit 1; }
	@sed -i.bak -e 's/^# Version: .*/# Version: $(V)/' -e 's/^_TUIN_VERSION=.*/_TUIN_VERSION="$(V)"/' tuin.sh && rm -f tuin.sh.bak
	@grep -q '_TUIN_VERSION="$(V)"' tuin.sh && echo "bumped to $(V)"
```

Add `bump` to `.PHONY` and to the `help` and `release` text (step 2 becomes `make bump V=X.Y.Z`).

**Step 3: Run everything**

Run: `PATH=/bin:/usr/bin:$PATH make test && make lint`
Expected: green.

**Step 4: Commit**

```bash
git add README.md AGENTS.md CHANGELOG.md Makefile tuin.sh docs/ROADMAP.md tests/test_docs.bats tests/test_release.bats
git commit -m "docs: keyboard reference, env-var table, roadmap; make bump target"
```

---

### Task 12: Manual smoke and release prep

**Step 1: Run the examples by hand** in a real terminal, bash 3.2 and bash 5 if available:

```bash
bash examples/full_demo.sh
bash examples/cascading_menu.sh
```

Check: arrows, j/k, digits, ESC feels instant on bash 5 and takes ~1 s on bash 3.2, Ctrl-Z then `fg` redraws cleanly, Ctrl-C once exits with a sane prompt, resizing the window mid-list redraws.

**Step 2: Do not tag.** Leave `[Unreleased]` in the changelog. The release itself follows `RELEASING.md` when the user says so.
