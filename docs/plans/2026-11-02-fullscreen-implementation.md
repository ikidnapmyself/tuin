# Fullscreen Mode and Logo Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship tuin 0.3.0 with `tuin_fullscreen on|off|clear`, `tuin_logo`, and a row budget so lists fit under a logo.

**Architecture:** Two new public functions in `tuin.sh`. `tuin_fullscreen` switches the alternate screen on `/dev/tty` and probes once whether the terminal answers cursor-position queries. `tuin_choose` asks the terminal for its start row when fullscreen is on and sizes its window to the rows left. `tuin_logo` prints `$TUIN_LOGO`, else `assets/logo.txt` beside `tuin.sh`, else a tulip embedded in `tuin.sh`.

**Tech Stack:** bash 3.2, bats-core with the existing pty harness (`tests/test_helper/pty.bash`), shellcheck.

Design: `docs/plans/2026-11-02-fullscreen-design.md`.

## Deviations from the design doc

These came out of reading the code. Mention them to the owner at handoff.

1. The cursor-row query runs only while fullscreen is on, not for every inline `tuin_choose`. The pty harness has no terminal that answers, and an unanswered query would swallow test keystrokes.
2. The "does this terminal answer?" probe runs once inside `tuin_fullscreen on`, not inside `tuin_choose`. Callers capture with `x=$(tuin_choose ...)`, a subshell, so a flag set there would never persist. `on` runs in the parent shell, so its flag is inherited by every later subshell.
3. Keys typed before a list opens are discarded. The reply read consumes everything up to the `R`. Document it, don't fight it.
4. The default logo is drawn in the existing accent color only. `logo.txt` can't carry color. Multicolor is a later change.
5. `assets/logo.txt` and the embedded fallback are ASCII only. That satisfies the non-UTF-8 fallback without a locale branch.

## Conventions

- Tests: `tests/test_*.bats`, run one file with `tests/test_helper/bats-core/bin/bats tests/test_x.bats`, all with `make test`. Lint with `make lint`.
- `bash` on PATH is 3.2.57. Keep it that way. No `mapfile`, no associative arrays.
- No code comments unless the code can't express the point. The owner's global rule.
- Commit trailer on every commit: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never add a session URL.
- No third-party names anywhere. Examples use placeholder data.

---

### Task 0: Branch

**Step 1:** The design doc is already on `main`. Branch from it.

Run: `git switch -c feat/fullscreen`
Expected: `Switched to a new branch 'feat/fullscreen'`

**Step 2:** Baseline.

Run: `make test 2>&1 | tail -5`
Expected: all tests pass, no `not ok` lines. Note the total so later runs can be compared.

---

### Task 1: `tuin_fullscreen`

**Files:**
- Modify: `tuin.sh` (globals near line 33, helpers near line 263, public function after `tuin_section` near line 335, header comment lines 7-16)
- Create: `tests/test_fullscreen.bats`

**Step 1: Write the failing tests**

Create `tests/test_fullscreen.bats`:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "fullscreen: on, clear and off are silent no-ops without a terminal" {
    run bash -c "source '$TUIN_SH'; tuin_fullscreen on; a=\$?; tuin_fullscreen clear; b=\$?; tuin_fullscreen off; echo \"\$a\$b\$?\"" </dev/null
    assert_success
    assert_output 000
}

@test "fullscreen: a bad argument returns 2 and prints usage" {
    run bash -c "source '$TUIN_SH'; tuin_fullscreen sideways </dev/null"
    assert_failure 2
    assert_output --partial 'usage'
}

@test "fullscreen: on enters the alternate screen and off leaves it" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; tuin_fullscreen off; echo done'
    [ "$pty_out" = done ]
    [[ "$pty_tty" == *$'\033[?1049h'*$'\033[?1049l'* ]]
}

@test "fullscreen: on and off are idempotent" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen off; tuin_fullscreen on; tuin_fullscreen on; tuin_fullscreen off; tuin_fullscreen off; echo done'
    local h l
    h=$(printf '%s' "$pty_tty" | grep -o '1049h' | wc -l | tr -d ' ')
    l=$(printf '%s' "$pty_tty" | grep -o '1049l' | wc -l | tr -d ' ')
    [ "$h" = 1 ]
    [ "$l" = 1 ]
}

@test "fullscreen: clear blanks the screen and homes the cursor" {
    tuin_pty '' -- 'tuin_fullscreen clear; echo done'
    [[ "$pty_tty" == *$'\033[2J\033[H'* ]]
}

@test "fullscreen: on installs an EXIT backstop that leaves the alternate screen" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; echo done'
    [[ "$pty_tty" == *$'\033[?1049h'*$'\033[?1049l'* ]]
}

@test "fullscreen: the EXIT backstop also hands the tty back" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; trap -p EXIT'
    [[ "$pty_out" == *_tuin_tty_leave* ]]
}

@test "fullscreen: a caller EXIT trap is left alone" {
    tuin_pty '\033[1;1R' -- 'trap "echo caller-exit" EXIT; tuin_fullscreen on; trap -p EXIT'
    [[ "$pty_out" == *caller-exit* ]]
    [[ "$pty_out" != *"tuin_fullscreen off"* ]]
}

@test "fullscreen: off removes its own EXIT trap" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; tuin_fullscreen off; trap -p EXIT | wc -l'
    [ "$(printf '%s' "$pty_out" | tr -d ' ')" = 0 ]
}

@test "fullscreen: off keeps a trap the caller set after on" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; trap "echo mine" EXIT; tuin_fullscreen off; trap -p EXIT'
    [[ "$pty_out" == *mine* ]]
}

@test "fullscreen: a terminal that answers the position query is recorded" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; echo "cpr=$_TUIN_CPR"'
    [ "$pty_out" = cpr=1 ]
}

@test "fullscreen: a silent terminal costs one timeout and is recorded" {
    tuin_pty '' -- 'tuin_fullscreen on; echo "cpr=$_TUIN_CPR"'
    [ "$pty_out" = cpr=0 ]
}
```

**Step 2: Run to verify failure**

Run: `tests/test_helper/bats-core/bin/bats tests/test_fullscreen.bats`
Expected: every test FAILS with `tuin_fullscreen: command not found` style errors.

**Step 3: Implement**

In `tuin.sh`, add to the globals block after `_TUIN_TRAPPED=0`:

```bash
_TUIN_FULLSCREEN=0
_TUIN_FS_OWN_EXIT=0
_TUIN_CPR=0
```

Add after `_tuin_tty_rows` (before the "Public API" banner):

```bash
_tuin_cursor_row() {
    local reply re=$'\033\\[([0-9]+);[0-9]+$'
    printf '\033[6n' >&3
    IFS= read -rs -d R -t 1 reply <&3 || return 1
    [[ "$reply" =~ $re ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}
```

Add after `tuin_section`:

```bash
tuin_fullscreen() {
    case "${1:-}" in
        on)
            (( _TUIN_FULLSCREEN )) && return 0
            _tuin_choose_interactive || return 0
            if _tuin_tty_enter; then
                _tuin_cursor_row >/dev/null && _TUIN_CPR=1
                _tuin_tty_leave
            fi
            printf '\033[?1049h\033[2J\033[H' >/dev/tty
            _TUIN_FULLSCREEN=1
            if [[ -z "$(trap -p EXIT)" ]]; then
                _TUIN_FS_OWN_EXIT=1
                trap '_tuin_tty_leave; tuin_fullscreen off' EXIT
            fi
            ;;
        off)
            (( _TUIN_FULLSCREEN )) || return 0
            printf '\033[?1049l' >/dev/tty 2>/dev/null
            _TUIN_FULLSCREEN=0
            if (( _TUIN_FS_OWN_EXIT )); then
                [[ "$(trap -p EXIT)" == *"tuin_fullscreen off"* ]] && trap - EXIT
                _TUIN_FS_OWN_EXIT=0
            fi
            ;;
        clear)
            _tuin_choose_interactive || return 0
            printf '\033[2J\033[H' >/dev/tty
            ;;
        *)
            printf 'tuin: usage: tuin_fullscreen on|off|clear\n' >&2
            return 2
            ;;
    esac
    return 0
}
```

Add to the header comment's Public API list in `tuin.sh`:

```
#   tuin_fullscreen on|off|clear     Alternate screen for a whole-screen flow
```

**Step 4: Run to verify pass**

Run: `tests/test_helper/bats-core/bin/bats tests/test_fullscreen.bats`
Expected: all PASS.

If a pty test is flaky on the key timing, raise `TUIN_PTY_LEAD` for that test, as other test files do. Do not weaken assertions.

**Step 5: Lint and full suite**

Run: `make lint && make test 2>&1 | tail -5`
Expected: shellcheck clean. The AGENTS.md coverage test in `tests/test_docs.bats` now FAILS because `tuin_fullscreen` isn't documented yet. That's expected and fixed in Task 6. Every other test passes.

**Step 6: Commit**

```bash
git add tuin.sh tests/test_fullscreen.bats
git commit -m "feat: add tuin_fullscreen for the alternate screen" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `tuin_logo`

**Files:**
- Modify: `tuin.sh`
- Create: `assets/logo.txt`, `tests/test_logo.bats`

**Step 1: Write the failing tests**

Create `tests/test_logo.bats`:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
    WORK="$BATS_TEST_TMPDIR/vendored"
    mkdir -p "$WORK"
    cp "$TUIN_SH" "$WORK/tuin.sh"
}

colored() {
    bash -c "source '$1'; _TUIN_CYAN=\$'\\033[36m'; _TUIN_RESET=\$'\\033[0m'; tuin_logo"
}

@test "logo: with no assets beside tuin.sh it prints the embedded tulip" {
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_success
    [ "${#lines[@]}" -ge 4 ]
    [ "${#lines[@]}" -le 6 ]
}

@test "logo: assets/logo.txt beside tuin.sh beats the embedded tulip" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: TUIN_LOGO beats assets/logo.txt" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    printf 'FROM-ENV\n' > "$BATS_TEST_TMPDIR/mine.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/mine.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'FROM-ENV'
}

@test "logo: an unreadable TUIN_LOGO falls through to assets" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/missing.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: assets are found after the caller changes directory" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    run bash -c "cd '$WORK' && source ./tuin.sh && cd / && tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: control bytes in an override are stripped" {
    printf 'A\033[2JB\007\n' > "$BATS_TEST_TMPDIR/evil.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/evil.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'A[2JB'
}

@test "logo: the default tulip uses the accent color and an override does not" {
    run colored "$WORK/tuin.sh"
    [[ "$output" == *$'\033[36m'* ]]
    printf 'PLAIN\n' > "$BATS_TEST_TMPDIR/mine.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/mine.txt"
    run colored "$WORK/tuin.sh"
    [[ "$output" != *$'\033'* ]]
}

@test "logo: the repo's assets/logo.txt is non-empty, short and ASCII only" {
    [ -s "$TUIN_REPO_ROOT/assets/logo.txt" ]
    local n
    n=$(wc -l < "$TUIN_REPO_ROOT/assets/logo.txt" | tr -d ' ')
    [ "$n" -le 12 ]
    run env LC_ALL=C grep -n '[^[:print:]]' "$TUIN_REPO_ROOT/assets/logo.txt"
    assert_failure
}

@test "logo: tuin.sh run from the repo prints assets/logo.txt" {
    run bash -c "source '$TUIN_SH'; tuin_logo"
    assert_output "$(cat "$TUIN_REPO_ROOT/assets/logo.txt")"
}

@test "logo: centers on a terminal of known width" {
    printf 'ab\n' > "$BATS_TEST_TMPDIR/two.txt"
    tuin_pty '' -- "export TUIN_LOGO='$BATS_TEST_TMPDIR/two.txt'; _tuin_tty_cols() { echo 20; }; tuin_logo >/dev/tty"
    local pad
    printf -v pad '%9s' ''
    [[ "$pty_tty" == *"${pad}ab"* ]]
}

@test "logo: does not center when the width is unknown" {
    printf 'ab\n' > "$BATS_TEST_TMPDIR/two.txt"
    tuin_pty '' -- "export TUIN_LOGO='$BATS_TEST_TMPDIR/two.txt'; _tuin_tty_cols() { echo 0; }; tuin_logo >/dev/tty"
    [[ "$pty_tty" != *" ab"* ]]
}

@test "logo: always returns 0" {
    export TUIN_LOGO="$BATS_TEST_TMPDIR/missing.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo; echo rc=\$?"
    assert_line 'rc=0'
}
```

**Step 2: Run to verify failure**

Run: `tests/test_helper/bats-core/bin/bats tests/test_logo.bats`
Expected: FAIL, `tuin_logo` not found, and the repo-asset tests fail on the missing file.

**Step 3: Create the default art**

Create `assets/logo.txt` (ASCII only, 12 lines or fewer). This is a placeholder design. The owner may swap in another and no test depends on its shape:

```
   ,\  |  /,
   | \ | / |
   \  \|/  /
    \     /
     '._.'
       |
    \  |  /
     \ | /
      \|/
       |
     t u i n
```

**Step 4: Implement**

In `tuin.sh`, right after `_TUIN_LOADED=1`:

```bash
case "${BASH_SOURCE[0]}" in
    */*) _TUIN_ASSETS_DIR=$(CDPATH= cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd) ;;
    *)   _TUIN_ASSETS_DIR=$(pwd) ;;
esac
[[ -n "$_TUIN_ASSETS_DIR" ]] && _TUIN_ASSETS_DIR="$_TUIN_ASSETS_DIR/assets"
```

The directory is resolved at source time because a caller may `cd` after sourcing. Sourcing by bare name through `PATH` resolves to the wrong directory, so the logo falls back to the embedded tulip. Accept that.

Add after `_tuin_tty_rows`:

```bash
_tuin_tty_cols() {
    local r c
    read -r r c < <({ stty size </dev/tty; } 2>/dev/null)
    [[ "$c" =~ ^[0-9]+$ ]] || c=0
    printf '%d\n' "$c"
}
```

Add after `tuin_fullscreen`:

```bash
_tuin_logo_embedded() {
    printf '%s\n' \
        '  \ | /' \
        '  |\|/|' \
        '   \_/' \
        '    |' \
        '  \_|_/'
}

_tuin_logo_collect() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//[[:cntrl:]]/}"
        art+=("$line")
        (( ${#line} > max )) && max=${#line}
    done
    return 0
}

tuin_logo() {
    local src="" color="$_TUIN_CYAN" reset="$_TUIN_RESET"
    if [[ -n "${TUIN_LOGO:-}" && -f "$TUIN_LOGO" && -r "$TUIN_LOGO" ]]; then
        src="$TUIN_LOGO"
        color=""
        reset=""
    elif [[ -n "$_TUIN_ASSETS_DIR" && -r "$_TUIN_ASSETS_DIR/logo.txt" ]]; then
        src="$_TUIN_ASSETS_DIR/logo.txt"
    fi

    local art=() max=0 cols=0 pad=0 lead="" line
    if [[ -n "$src" ]]; then
        _tuin_logo_collect < "$src"
    else
        _tuin_logo_collect < <(_tuin_logo_embedded)
    fi
    (( ${#art[@]} )) || return 0

    [[ -t 1 ]] && cols=$(_tuin_tty_cols)
    (( cols > max )) && pad=$(( (cols - max) / 2 ))
    (( pad > 0 )) && printf -v lead '%*s' "$pad" ''
    for line in "${art[@]}"; do
        printf '%s%s%s%s\n' "$lead" "$color" "$line" "$reset"
    done
    return 0
}
```

Add to the header Public API list:

```
#   tuin_logo                        Print the tulip logo ($TUIN_LOGO overrides)
```

**Step 5: Run to verify pass**

Run: `tests/test_helper/bats-core/bin/bats tests/test_logo.bats`
Expected: all PASS.

**Step 6: Security and lint checks**

Run: `tests/test_helper/bats-core/bin/bats tests/test_security.bats && make lint`
Expected: PASS and shellcheck clean. No `eval`, no unquoted `$@`, no indirect expansion was introduced.

**Step 7: Commit**

```bash
git add tuin.sh assets/logo.txt tests/test_logo.bats
git commit -m "feat: add tuin_logo with a TUIN_LOGO override" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Row budget in `tuin_choose`

**Files:**
- Modify: `tuin.sh` (`tuin_choose` locals and first draw near lines 499-529, `_tuin_choose_draw` near line 637)
- Modify: `tests/test_fullscreen.bats` (append)

**Step 1: Write the failing tests**

Append to `tests/test_fullscreen.bats`. Each reply `\033[R;1R` answers one query. The first answers the probe in `tuin_fullscreen on`, the second answers the query in `tuin_choose`.

```bash
@test "fullscreen: a list fits the rows left below the cursor" {
    tuin_pty '\033[1;1R\033[4;1R%PAUSE%\033[F\r' -- 'stty rows 10; tuin_fullscreen on; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 40 ]
    [[ "$pty_tty" == *"> 40"* ]]
    [[ "$pty_tty" == *"  37"* ]]
    [[ "$pty_tty" != *"  36"* ]]
}

@test "fullscreen: a silent terminal falls back to height minus 3 for that call" {
    tuin_pty '\033[1;1R%PAUSE%\033[F\r' -- 'stty rows 10; tuin_fullscreen on; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 40 ]
    [[ "$pty_tty" == *"  34"* ]]
}

@test "fullscreen: a plain tuin_choose never asks for the cursor position" {
    tuin_pty '\r' -- 'tuin_choose a b c'
    [[ "$pty_tty" != *$'\033[6n'* ]]
}

@test "fullscreen: tuin_choose still returns its result through command substitution" {
    tuin_pty '\033[1;1R\033[1;1R\033[B\r' -- 'tuin_fullscreen on; x=$(tuin_choose a b c); tuin_fullscreen off; echo "$x"'
    [ "$pty_out" = b ]
}

@test "fullscreen: tuin_menu counts its title line in the row budget" {
    tuin_pty '\033[1;1R\033[2;1R\r' -- 'tuin_fullscreen on; tuin_menu T A B; echo "rc=$? reply=$TUIN_REPLY"'
    [ "$pty_out" = 'rc=0 reply=A' ]
}
```

**Step 2: Run to verify failure**

Run: `tests/test_helper/bats-core/bin/bats tests/test_fullscreen.bats`
Expected: the first test FAILS because the window is still 7 rows (`  36` is present). The others may pass already or stall on unanswered input. Note which.

**Step 3: Implement**

In `tuin_choose`, add `list_row` to the locals line:

```bash
    local selected=0 top=0 rows=0 max_rows=0 last_height=0 list_row=0
```

Just before the first `_tuin_choose_draw` call:

```bash
    if (( _TUIN_FULLSCREEN && _TUIN_CPR )); then
        list_row=$(_tuin_cursor_row) || list_row=0
    fi
```

In `_tuin_choose_draw`, replace the `max_rows` computation:

```bash
    if (( max_rows == 0 || _TUIN_REDRAW )); then
        if (( list_row > 0 )); then
            max_rows=$(( $(_tuin_tty_rows) - list_row - filter_enabled - hints ))
        else
            max_rows=$(( $(_tuin_tty_rows) - 3 ))
        fi
        (( max_rows < 1 )) && max_rows=1
        _TUIN_REDRAW=0
    fi
```

At `list_row=1` with the filter and hints on, the result is height minus 3, the same as today. That's the check that the old behavior is preserved at the top of the screen.

**Step 4: Run to verify pass**

Run: `tests/test_helper/bats-core/bin/bats tests/test_fullscreen.bats tests/test_choose.bats tests/test_menu.bats`
Expected: all PASS. If a `%PAUSE%` ordering is flaky, keep both replies in the first chunk. The second query must be answered inside its 1s read.

**Step 5: Full suite and lint**

Run: `make lint && make test 2>&1 | tail -5`
Expected: only the AGENTS.md coverage test still FAILS (fixed in Task 6).

**Step 6: Commit**

```bash
git add tuin.sh tests/test_fullscreen.bats
git commit -m "feat(choose): fit the list to the rows left below the cursor in fullscreen" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Logo SVG

**Files:**
- Create: `assets/logo.svg`

**Step 1:** Create `assets/logo.svg`. Mid-gray text and saturated fills read on both light and dark GitHub themes.

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 300" width="240" height="300" role="img" aria-labelledby="t">
  <title id="t">tuin</title>
  <path d="M120 150 C120 190 118 225 120 250" stroke="#2f9e44" stroke-width="8" fill="none" stroke-linecap="round"/>
  <path d="M120 215 C85 215 62 195 55 165 C85 170 110 190 120 215 Z" fill="#37b24d"/>
  <path d="M120 215 C155 215 178 195 185 165 C155 170 130 190 120 215 Z" fill="#2f9e44"/>
  <path d="M120 150 C85 150 70 110 75 60 C95 80 110 95 120 100 C130 95 145 80 165 60 C170 110 155 150 120 150 Z" fill="#e03131"/>
  <path d="M120 150 C100 140 95 100 120 100 C145 100 140 140 120 150 Z" fill="#c92a2a"/>
  <text x="120" y="288" text-anchor="middle" font-family="ui-monospace, Menlo, Consolas, monospace" font-size="28" fill="#868e96">tuin</text>
</svg>
```

**Step 2:** Render it and look.

Run: `qlmanage -t -s 400 -o "$TMPDIR" assets/logo.svg && open "$TMPDIR/logo.svg.png"`
Expected: a red three-petal tulip on a green stem with two leaves and the word `tuin` below. Adjust the paths until it reads as a tulip. Show the owner the render.

**Step 3: Commit**

```bash
git add assets/logo.svg
git commit -m "docs: add the tulip logo as SVG" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Example

**Files:**
- Create: `examples/dashboard.sh`
- Modify: `examples/README.md`

**Step 1:** Create `examples/dashboard.sh` with placeholder data only:

```bash
#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

items=(
    "HIGH  item-01  queue backlog above threshold"
    "MED   item-02  certificate expires in 6 days"
    "LOW   item-03  disk at 71 percent"
)

open_item() {
    local item=$1
    while tuin_menu "$item" "Show details" "Acknowledge" "Escalate"; do
        case $TUIN_REPLY in
            "Show details")
                tuin_section "Details"
                printf '%s\n' "$item"
                tuin_confirm "Back to actions?" y || return 0
                ;;
            "Acknowledge"|"Escalate")
                tuin_spin "$TUIN_REPLY" -- sleep 1
                return 0
                ;;
        esac
    done
    return 0
}

tuin_fullscreen on
while :; do
    tuin_fullscreen clear
    tuin_logo
    tuin_section "Open items"
    item=$(tuin_choose "${items[@]}") || break
    open_item "$item"
done
tuin_fullscreen off
```

**Step 2:** Add a row to the table in `examples/README.md`:

```
| `dashboard.sh` | `tuin_fullscreen` + `tuin_logo` + `tuin_choose` + `tuin_menu` + `tuin_spin` |
```

**Step 3: Lint**

Run: `make lint`
Expected: clean.

**Step 4: Run it in a real terminal.** The owner does this, since it needs a live terminal.

Run: `! bash examples/dashboard.sh`
Expected: the screen clears, the tulip prints, the list opens under it, picking an item opens the action menu, Back returns to the list, `q` leaves and the original scrollback is intact. Try a small window, a long list, `NO_COLOR=1`, and `TUIN_LOGO=/path/to/other.txt`.

**Step 5: Commit**

```bash
git add examples/dashboard.sh examples/README.md
git commit -m "docs: add a fullscreen dashboard example" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Docs

**Files:**
- Modify: `README.md`, `AGENTS.md`, `docs/ROADMAP.md`, `CHANGELOG.md`

`tests/test_docs.bats` already enforces that `AGENTS.md` names every public function and that `README.md` names every `${TUIN_*}` variable used in `tuin.sh`. Those two tests are the failing tests for this task.

**Step 1: Confirm the failing tests**

Run: `tests/test_helper/bats-core/bin/bats tests/test_docs.bats`
Expected: FAIL on `tuin_fullscreen`, `tuin_logo` missing from AGENTS.md and `TUIN_LOGO` missing from README.md.

**Step 2: README.md**

- Insert above the `# 🌷 tuin` heading: `<p align="center"><img src="assets/logo.svg" width="120" alt="tuin"></p>`
- Change the "Nine functions" sentence to "Eleven functions".
- Change line 33 ("You need full-screen layouts, mouse support, or complex widgets") to "You need split-pane layouts, live-refreshing dashboards, mouse support, or complex widgets".
- After the `tuin_section` heading section, add:

````markdown
### `tuin_fullscreen on|off|clear`

Runs a whole-screen flow on the terminal's alternate screen. `on` switches to
it and clears it. `off` switches back, and your scrollback is untouched.
`clear` blanks the screen and homes the cursor, so each screen of your flow
starts fresh. `on` and `off` are idempotent. Returns `0`, or `2` for an unknown
argument.

```bash
source tuin.sh
tuin_fullscreen on
while :; do
    tuin_fullscreen clear
    tuin_logo
    item=$(tuin_choose "${items[@]}") || break
done
tuin_fullscreen off
```

While fullscreen is on, `tuin_choose` and `tuin_menu` size their list to the
rows left below the cursor, so a logo or header above them doesn't push the
list off the screen. tuin asks the terminal for its cursor row to do this, and
keys typed just before a list opens are discarded. A terminal that doesn't
answer costs one second at `on` and lists fall back to the terminal height
minus three.

`on` installs an `EXIT` trap that leaves the alternate screen, but only if you
have none. If you have your own, add `tuin_fullscreen off` to it.

**Non-TTY fallback:** all three are silent no-ops that return `0`.

### `tuin_logo`

Prints the tulip. The caller places it, the way `tuin_banner` works. Returns
`0`. The art comes from the first of these that exists:

1. The file named by `TUIN_LOGO`.
2. `assets/logo.txt` beside `tuin.sh`.
3. A small tulip embedded in `tuin.sh`, so a vendored single file still shows
   something.

The default tulip is drawn in the accent color unless `NO_COLOR` is set. A
`TUIN_LOGO` file is printed as plain text with control bytes stripped, so it
can't repaint your terminal. It is centered when stdout is a terminal of known
width. tuin never copies or writes your logo, so keep it wherever your project
keeps assets.
````

- Add to the Environment variables table:

```
| `TUIN_LOGO` | Path to a plain-text file that `tuin_logo` prints instead of the built-in tulip. Unreadable paths are ignored. |
```

- In the Examples table add `examples/dashboard.sh` with `tuin_fullscreen` + `tuin_logo` + `tuin_choose` + `tuin_menu` + `tuin_spin`.
- In "What's not in tuin" remove "an alternate-screen \"fullscreen TUI\" mode" and add "split panes and live-refreshing dashboards".

**Step 3: AGENTS.md**

- Add two rows to the API table:

```
| `tuin_fullscreen` | `tuin_fullscreen on\|off\|clear` | — | `0`; `2` on a bad argument |
| `tuin_logo` | `tuin_logo` | the tulip, or `$TUIN_LOGO`'s file | `0` |
```

- Add `TUIN_LOGO` (path to a plain-text logo for `tuin_logo`) to rule 7's list of environment knobs.
- Change "or need full-screen/mouse UIs" in the intro to "or need split-pane, live-refresh or mouse UIs".
- Add a canonical snippet "Fullscreen screen-at-a-time flow" with the same loop as the README, and one rule: pair `tuin_fullscreen on` with `tuin_fullscreen off`, and add `off` to your own `EXIT` trap if you have one.

**Step 4: docs/ROADMAP.md**

- Under "Landed since v0.1.0" add: "`tuin_fullscreen` and `tuin_logo` (0.3.0): the alternate screen, a branded header, and a row budget so lists fit under it."
- Delete the "Alternate-screen fullscreen TUI mode" row from "Still deferred".
- Add rows: "Live auto-refresh | Needs an event loop and a sub-second `select` timeout. bash 3.2's whole-second `read -t` makes it rough." and "Split panes | Needs a layout engine and cursor addressing per region. Framework territory."

**Step 5: CHANGELOG.md**

Add above `## [0.2.0]`, mirroring the existing entry's style:

```markdown
## [Unreleased]

### Added
- `tuin_fullscreen on|off|clear` for whole-screen flows on the alternate screen.
- `tuin_logo`, with a tulip in `assets/logo.txt`, an embedded fallback for a
  vendored single file, and a `TUIN_LOGO` override.
- `assets/logo.svg` for the README.
- `examples/dashboard.sh`.

### Changed
- While fullscreen is on, `tuin_choose` and `tuin_menu` size their list to the
  rows below the cursor instead of assuming the top of the screen.
```

**Step 6: Run to verify pass**

Run: `make lint && make test 2>&1 | tail -5`
Expected: everything passes, including the two docs tests.

**Step 7: Commit**

```bash
git add README.md AGENTS.md docs/ROADMAP.md CHANGELOG.md
git commit -m "docs: document fullscreen mode and the logo" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Verify and prepare the 0.3.0 release

**Step 1:** Use superpowers:verification-before-completion. Run and read the output of:

```bash
make lint
make test 2>&1 | tail -15
git status --short
```

Expected: shellcheck clean, all tests pass, tree clean. Confirm no untracked file was left by a test.

**Step 2:** Bump. The Makefile refuses a dirty tree.

Run: `make bump V=0.3.0`
Expected: `bumped to 0.3.0`

**Step 3:** Re-run `make test 2>&1 | tail -5`. Expected: pass. `tuin_version` is asserted by shape and consistency, so it should not need edits.

**Step 4:** Commit the bump.

```bash
git add tuin.sh
git commit -m "chore: bump version to 0.3.0" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

**Step 5:** Record the digest, as 0.2.0 did.

Run: `make checksum`
Edit `CHANGELOG.md`: rename `## [Unreleased]` to `## [0.3.0] - <today>` and add the digest block under it in the same format as 0.2.0.

```bash
git add CHANGELOG.md
git commit -m "docs: record the 0.3.0 sha-256 digest" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

The digest must be taken after the last change to `tuin.sh`. If `tuin.sh` changes later, redo this step.

**Step 6: Stop.** Do not tag, push, or open a PR without the owner's go-ahead. Offer superpowers:finishing-a-development-branch.
