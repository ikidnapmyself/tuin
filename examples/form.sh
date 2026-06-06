#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

name=$(tuin_input "Enter your name" "World")
if tuin_confirm "Greet $name?" y; then
    tuin_banner "Hello, $name!"
fi
