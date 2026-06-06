#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

@test "tuin_spin non-TTY runs command and inherits exit code 0" {
    run bash -c "source '$TUIN_SH' && tuin_spin 'noop' -- true </dev/null"
    assert_success
}

@test "tuin_spin non-TTY runs command and inherits exit code 1" {
    run bash -c "source '$TUIN_SH' && tuin_spin 'fail' -- false </dev/null"
    assert_failure 1
}

@test "tuin_spin non-TTY emits no ANSI escapes" {
    run bash -c "source '$TUIN_SH' && tuin_spin 'echo it' -- echo hi </dev/null"
    assert_success
    refute_output --partial $'\033'
    assert_output --partial "hi"
}

@test "tuin_spin non-TTY passes inner command stdout through" {
    run bash -c "source '$TUIN_SH' && tuin_spin 'cat' -- printf 'pass-through\n' </dev/null"
    assert_success
    assert_output "pass-through"
}
