#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "tuin_input non-TTY echoes typed value" {
    run bash -c "source '$TUIN_SH' && echo 'Alice' | tuin_input 'Name'"
    assert_success
    assert_output "Alice"
}

@test "tuin_input non-TTY empty + default returns default" {
    run bash -c "source '$TUIN_SH' && printf '\n' | tuin_input 'Name' 'World'"
    assert_success
    assert_output "World"
}

@test "tuin_input non-TTY no default + empty input returns empty" {
    run bash -c "source '$TUIN_SH' && printf '\n' | tuin_input 'Name'"
    assert_success
    assert_output ""
}

@test "tuin_input non-TTY passes regex-matching value through" {
    run bash -c "source '$TUIN_SH' && echo 'abc' | tuin_input 'Letters' '' '^[a-z]+$'"
    assert_success
    assert_output "abc"
}
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
