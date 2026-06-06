#!/usr/bin/env bash
# Common BATS setup — sourced from every test file.

_common_setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    # Absolute path to the repo root (one level above tests/)
    TUIN_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TUIN_SH="$TUIN_REPO_ROOT/tuin.sh"
    export TUIN_REPO_ROOT TUIN_SH
}
