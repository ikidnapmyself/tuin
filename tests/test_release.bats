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

@test "make bump refuses a dirty tree and rewrites both version locations" {
    tmp=$(mktemp -d)
    cp "$TUIN_REPO_ROOT/Makefile" "$TUIN_REPO_ROOT/tuin.sh" "$TUIN_REPO_ROOT/README.md" "$tmp/"
    git -C "$tmp" init -q && git -C "$tmp" add -A && git -C "$tmp" -c user.email=t@t -c user.name=t commit -qm init
    run make -C "$tmp" bump V=9.9.9
    assert_success
    run grep -c '9\.9\.9' "$tmp/tuin.sh"
    assert_output 2
    echo x >> "$tmp/README.md"
    run make -C "$tmp" bump V=9.9.10
    assert_failure
}
