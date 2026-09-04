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
