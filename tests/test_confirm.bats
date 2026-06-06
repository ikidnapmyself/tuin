#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
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