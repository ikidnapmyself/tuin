#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
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
