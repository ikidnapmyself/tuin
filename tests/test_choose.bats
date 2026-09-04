#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "tuin_choose with no options returns 2" {
    run bash -c "source '$TUIN_SH' && tuin_choose"
    assert_failure 2
}

@test "tuin_choose non-TTY stdin '2' prints second option" {
    run bash -c "source '$TUIN_SH' && echo 2 | tuin_choose alpha bravo charlie"
    assert_success
    assert_output "bravo"
}

@test "tuin_choose non-TTY empty stdin prints first option" {
    run bash -c "source '$TUIN_SH' && printf '\n' | tuin_choose alpha bravo"
    assert_success
    assert_output "alpha"
}

@test "tuin_choose non-TTY out-of-range stdin prints first option" {
    run bash -c "source '$TUIN_SH' && echo 99 | tuin_choose alpha bravo"
    assert_success
    assert_output "alpha"
}

@test "tuin_choose non-TTY non-numeric stdin prints first option" {
    run bash -c "source '$TUIN_SH' && echo hello | tuin_choose alpha bravo"
    assert_success
    assert_output "alpha"
}

@test "tuin_choose non-TTY zero stdin prints first option" {
    run bash -c "source '$TUIN_SH' && echo 0 | tuin_choose alpha bravo"
    assert_success
    assert_output "alpha"
}

# Regression guard: pre-hoist, these helpers were defined inside tuin_choose,
# so a bare `source tuin.sh` left them undefined until the first call. Asserts
# they are installed at source time, not lazily on first use.
@test "tuin_choose helpers exist immediately after source (no lazy install)" {
    run bash -c "source '$TUIN_SH' && declare -F _tuin_choose_apply_filter _tuin_choose_render"
    assert_success
}

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
    tuin_pty 'zzz\033%PAUSE%\r' -- 'tuin_choose a b c d e f g h i j k; echo "rc=$?"'
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
    local clear=$'\033[2J'
    tuin_pty '\r' -- "tuin_choose \$'ev\\033[2Jil' safe"
    [ "$pty_out" = $'ev\033[2Jil' ]
    [[ "$pty_tty" != *"$clear"* ]]
    [[ "$pty_tty" == *"ev[2Jil"* ]]
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
    tuin_pty 'j\r' -- 'b=$(tuin_stty_norm); tuin_choose a b >/dev/null; [[ "$b" == "$(tuin_stty_norm)" ]] && echo ok'
    [ "$pty_out" = ok ]
}

@test "choose: long list is clipped to the terminal height and scrolls" {
    tuin_pty '\033[F\r' -- 'stty rows 10; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 40 ]
    [[ "$pty_tty" == *"> 40"* ]]
    [[ "$pty_tty" != *"  33"* ]]
}

@test "choose: pgdn/pgup move by a page" {
    tuin_pty '\033[6~\r' -- 'stty rows 10; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 8 ]
    tuin_pty '\033[6~\033[6~\033[5~\r' -- 'stty rows 10; tuin_choose $(seq 1 40)'
    [ "$pty_out" = 8 ]
}

@test "choose: WINCH triggers a redraw with the new height" {
    tuin_pty '%PAUSE%\r' -- '
        stty rows 10
        ( sleep 0.5; stty rows 30 </dev/tty; kill -WINCH $PPID ) &
        tuin_choose $(seq 1 40)'
    [ "$pty_out" = 1 ]
    [[ "$pty_tty" == *"  20"* ]]
}
