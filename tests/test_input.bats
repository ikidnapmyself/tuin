#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
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