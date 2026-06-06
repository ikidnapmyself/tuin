#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

@test "_tuin_choose_filter empty filter returns all indices" {
    run bash -c "source '$TUIN_SH' && _tuin_choose_filter '' apple banana cherry"
    assert_success
    assert_output $'0\n1\n2'
}

@test "_tuin_choose_filter is case-insensitive substring match" {
    run bash -c "source '$TUIN_SH' && _tuin_choose_filter AN apple banana cherry"
    assert_success
    assert_output "1"
}

@test "_tuin_choose_filter no match returns empty" {
    run bash -c "source '$TUIN_SH' && _tuin_choose_filter zzz apple banana cherry"
    assert_success
    assert_output ""
}

@test "_tuin_choose_filter matches multiple items" {
    run bash -c "source '$TUIN_SH' && _tuin_choose_filter er berry cherry apple"
    assert_success
    assert_output $'0\n1'
}
