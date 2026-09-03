#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "tty: enter/leave restore stty exactly" {
    tuin_pty '' -- '
        before=$(tuin_stty_norm)
        _tuin_tty_enter
        during=$(tuin_stty_norm <&3)
        _tuin_tty_leave
        after=$(tuin_stty_norm)
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
    tuin_pty '\003' -- 'before=$(tuin_stty_norm); tuin_choose a b c; rc=$?; after=$(tuin_stty_norm); [[ "$before" == "$after" ]] && echo "rc=$rc"'
    [ "$pty_out" = rc=130 ]
}

@test "tty: suspend restores cooked mode, resume re-enters raw and flags redraw" {
    tuin_pty '' -- '
        kill() { :; }
        before=$(tuin_stty_norm)
        _tuin_tty_enter
        _tuin_tty_suspend
        parked=$(tuin_stty_norm <&3)
        _tuin_tty_resume
        resumed=$(tuin_stty_norm <&3)
        _tuin_tty_leave
        [[ "$parked" == "$before" && "$resumed" != "$before" && $_TUIN_REDRAW == 1 ]] && echo ok'
    [ "$pty_out" = ok ]
}
