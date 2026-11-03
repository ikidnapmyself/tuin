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
    [[ "$pty_tty" == *$'\033[?1049h'*$'\033[?1049l'* ]] || false
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
    [[ "$pty_tty" == *$'\033[2J\033[H'* ]] || false
}

@test "fullscreen: on installs an EXIT backstop that leaves the alternate screen" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; echo done'
    [[ "$pty_tty" == *$'\033[?1049h'*$'\033[?1049l'* ]] || false
}

@test "fullscreen: the EXIT backstop also hands the tty back" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; trap -p EXIT'
    [[ "$pty_out" == *_tuin_tty_leave* ]] || false
}

@test "fullscreen: a caller EXIT trap is left alone" {
    tuin_pty '\033[1;1R' -- 'trap "echo caller-exit" EXIT; tuin_fullscreen on; trap -p EXIT'
    [[ "$pty_tty" == *$'\033[?1049h'* ]] || false
    [[ "$pty_out" == *"echo caller-exit"* ]] || false
    [[ "$pty_out" != *"tuin_fullscreen off"* ]] || false
}

@test "fullscreen: off removes its own EXIT trap" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; a=$(trap -p EXIT); tuin_fullscreen off; b=$(trap -p EXIT); [[ -n "$a" && -z "$b" ]] && echo ok'
    [ "$pty_out" = ok ]
}

@test "fullscreen: off keeps a trap the caller set after on" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; trap "echo mine" EXIT; tuin_fullscreen off; trap -p EXIT'
    [[ "$pty_tty" == *$'\033[?1049h'*$'\033[?1049l'* ]] || false
    [[ "$pty_out" == *"echo mine"* ]] || false
}

@test "fullscreen: a terminal that answers the position query is recorded" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; echo "cpr=$_TUIN_CPR"'
    [ "$pty_out" = cpr=1 ]
}

@test "fullscreen: a silent terminal costs one timeout and is recorded" {
    tuin_pty '' -- 'tuin_fullscreen on; echo "cpr=$_TUIN_CPR"'
    [ "$pty_out" = cpr=0 ]
}

@test "fullscreen: off keeps a caller trap that itself calls tuin_fullscreen off" {
    tuin_pty '\033[1;1R' -- 'tuin_fullscreen on; trap "tuin_fullscreen off; echo cleanup" EXIT; tuin_fullscreen off; trap -p EXIT'
    [[ "$pty_out" == *"echo cleanup"* ]] || false
}

@test "fullscreen: on leaves a caller INT trap and the stty state untouched" {
    tuin_pty '\033[1;1R' -- 'trap "echo c" INT; before=$(tuin_stty_norm); tuin_fullscreen on; after=$(tuin_stty_norm); [[ "$before" == "$after" ]] && echo same; trap -p INT'
    [[ "$pty_out" == *same* ]] || false
    [[ "$pty_out" == *"echo c"* ]] || false
}

@test "fullscreen: a silent terminal is probed once per process" {
    tuin_pty '' -- 'tuin_fullscreen on; tuin_fullscreen off; tuin_fullscreen on; echo done'
    local n
    n=$(printf '%s' "$pty_tty" | grep -o $'\033\\[6n' | wc -l | tr -d ' ')
    [ "$pty_out" = done ]
    [ "$n" = 1 ]
}

@test "fullscreen: off is silent when the terminal cannot be opened" {
    if { : >/dev/tty; } 2>/dev/null; then
        skip "needs a process with no controlling terminal"
    fi
    run bash -c "source '$TUIN_SH'; _TUIN_FULLSCREEN=1; tuin_fullscreen off; echo rc=\$?" </dev/null
    assert_output rc=0
}

@test "fullscreen: a list in a subshell leaves the fullscreen EXIT trap in place" {
    tuin_pty '\033[1;1R\033[1;1R\r' -- 'tuin_fullscreen on; x=$(tuin_choose a b); echo "x=$x"; trap -p EXIT'
    [[ "$pty_out" == *x=a* ]] || false
    [[ "$pty_out" == *"trap -- '_tuin_tty_leave; tuin_fullscreen off' EXIT"* ]] || false
}

@test "fullscreen: Ctrl-C during the probe runs and keeps the caller INT trap" {
    tuin_pty '' -- 'trap "echo c" INT; before=$(tuin_stty_norm); (sleep 0.4; kill -INT 0) & tuin_fullscreen on; wait; after=$(tuin_stty_norm); [[ "$before" == "$after" ]] && echo same; echo "cpr=$_TUIN_CPR"; trap -p INT'
    printf '%s\n' "$pty_out" | grep -qx c
    [[ "$pty_out" == *same* ]] || false
    [[ "$pty_out" == *cpr=0* ]] || false
    [[ "$pty_out" == *"trap -- 'echo c' SIGINT"* ]] || false
}

@test "fullscreen: Ctrl-C during the probe restores stty when the caller has no trap" {
    tuin_pty '' -- 'trap : INT; before=$(tuin_stty_norm); ( (sleep 0.4; kill -INT 0) & tuin_fullscreen on; wait ); after=$(tuin_stty_norm); [[ "$before" == "$after" ]] && echo same'
    [ "$pty_out" = same ]
}

@test "fullscreen: a list fits the rows left below the cursor" {
    tuin_pty '\033[1;1R\033[4;1R%PAUSE%\033[F\r' -- 'stty rows 10; tuin_fullscreen on; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 40 ]
    [[ "$pty_tty" == *"> 40"* ]] || false
    [[ "$pty_tty" == *"  37"* ]] || false
    [[ "$pty_tty" != *"  36"* ]] || false
}

@test "fullscreen: a silent terminal falls back to height minus 3 for that call" {
    tuin_pty '\033[1;1R%PAUSE%%PAUSE%\033[F\r' -- 'stty rows 10; tuin_fullscreen on; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 40 ]
    [[ "$pty_tty" == *"  34"* ]] || false
}

@test "fullscreen: a plain tuin_choose never asks for the cursor position" {
    tuin_pty '\r' -- 'tuin_choose a b c'
    [[ "$pty_tty" != *$'\033[6n'* ]] || false
}

@test "fullscreen: tuin_choose still returns its result through command substitution" {
    tuin_pty '\033[1;1R\033[4;1R\033[F\r' -- 'stty rows 10; tuin_fullscreen on; x=$(tuin_choose $(seq 1 40)); tuin_fullscreen off; echo "$x"'
    local n
    n=$(printf '%s' "$pty_tty" | grep -o $'\033\\[6n' | wc -l | tr -d ' ')
    [ "$pty_out" = 40 ]
    [[ "$pty_tty" == *"  37"* ]] || false
    [[ "$pty_tty" != *"  36"* ]] || false
    [ "$n" = 2 ]
}

@test "fullscreen: tuin_menu counts its title line in the row budget" {
    tuin_pty '\033[1;1R\033[3;1R\033[6~\r' -- 'stty rows 8; tuin_fullscreen on; TUIN_FILTER=0 tuin_menu T $(seq 1 20); echo "rc=$? reply=$TUIN_REPLY"'
    local after_probe=${pty_tty#*$'\033[6n'}
    [ "$pty_out" = 'rc=0 reply=5' ]
    [[ "$pty_tty" == *"> 5"* ]] || false
    [[ "$pty_tty" != *"  6"* ]] || false
    [[ "$after_probe" == *$'T\r\n'*$'\033[6n'* ]] || false
}

@test "fullscreen: Ctrl-C during the row query returns 130 without drawing the list" {
    tuin_pty '\033[1;1R' -- 'trap : INT; tuin_fullscreen on; (sleep 0.3; kill -INT 0) & x=$(tuin_choose alpha-opt beta-opt); rc=$?; wait; tuin_fullscreen off; echo "rc=$rc x=$x"'
    local rest=${pty_tty#*$'\033[6n'}
    [ "$pty_out" = 'rc=130 x=' ]
    [[ "$rest" == *$'\033[6n'* ]] || false
    rest=${rest#*$'\033[6n'}
    [[ "$rest" != *alpha-opt* ]] || false
    [[ "$rest" != *beta-opt* ]] || false
}
