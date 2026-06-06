#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

@test "make checksum prints a 64-hex sha256 of tuin.sh" {
    run make -C "$TUIN_REPO_ROOT" checksum
    assert_success
    # assert_line (not assert_output) so make's "Entering/Leaving directory"
    # chatter under -C on some platforms doesn't break the anchored match.
    assert_line --regexp '^[0-9a-f]{64}  tuin\.sh$'
}

@test "make release checklist references publishing the digest" {
    run make -C "$TUIN_REPO_ROOT" release
    assert_success
    assert_output --partial "make checksum"
}
