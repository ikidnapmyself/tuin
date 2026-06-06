#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

@test "tuin_banner prints the title" {
    run bash -c "LC_ALL=C ; source '$TUIN_SH' && tuin_banner 'Hello'"
    assert_success
    assert_output --partial "Hello"
}

@test "tuin_banner uses ASCII when LC_ALL=C" {
    run bash -c "LC_ALL=C ; source '$TUIN_SH' && tuin_banner 'Hi'"
    assert_success
    assert_output --partial "+"
    refute_output --partial "╔"
}

@test "tuin_banner uses Unicode boxes when UTF-8" {
    run bash -c "LC_ALL=en_US.UTF-8 ; source '$TUIN_SH' && tuin_banner 'Hi'"
    assert_success
    assert_output --partial "╔"
}

@test "tuin_section prints the heading" {
    run bash -c "LC_ALL=C ; source '$TUIN_SH' && tuin_section 'Setup'"
    assert_success
    assert_output --partial "Setup"
}

@test "tuin_section uses === when LC_ALL=C" {
    run bash -c "LC_ALL=C ; source '$TUIN_SH' && tuin_section 'X'"
    assert_success
    assert_output --partial "==="
}

@test "tuin_section uses ═══ when UTF-8" {
    run bash -c "LC_ALL=en_US.UTF-8 ; source '$TUIN_SH' && tuin_section 'X'"
    assert_success
    assert_output --partial "═══"
}