#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "tuin_confirm non-TTY with 'y' returns 0" {
    run bash -c "source '$TUIN_SH' && echo 'y' | tuin_confirm 'Proceed?'"
    assert_success
}

@test "tuin_confirm non-TTY with 'Y' returns 0" {
    run bash -c "source '$TUIN_SH' && echo 'Y' | tuin_confirm 'Proceed?'"
    assert_success
}

@test "tuin_confirm non-TTY with 'n' returns 1" {
    run bash -c "source '$TUIN_SH' && echo 'n' | tuin_confirm 'Proceed?'"
    assert_failure 1
}

@test "tuin_confirm non-TTY empty + default=y returns 0" {
    run bash -c "source '$TUIN_SH' && printf '' | tuin_confirm 'Proceed?' y"
    assert_success
}

@test "tuin_confirm non-TTY empty + default=n returns 1" {
    run bash -c "source '$TUIN_SH' && printf '' | tuin_confirm 'Proceed?' n"
    assert_failure 1
}

@test "tuin_confirm non-TTY garbage input returns 1" {
    run bash -c "source '$TUIN_SH' && echo 'xyz' | tuin_confirm 'Proceed?'"
    assert_failure 1
}
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

@test "confirm: a stray arrow key is ignored, not a no" {
    tuin_pty '\033[B%PAUSE%y' -- 'tuin_confirm "Go?"; echo "rc=$?"'
    [ "$pty_out" = rc=0 ]
}

@test "confirm: Ctrl-C returns 130 with the tty restored" {
    tuin_pty '\003' -- 'b=$(tuin_stty_norm); tuin_confirm "Go?"; rc=$?; [[ "$b" == "$(tuin_stty_norm)" ]] && echo "rc=$rc"'
    [ "$pty_out" = rc=130 ]
}

@test "confirm: prompt shows the default indicator" {
    tuin_pty 'y' -- 'tuin_confirm "Go?" y'
    [[ "$pty_tty" == *"Go? [Y/n]"* ]]
}
