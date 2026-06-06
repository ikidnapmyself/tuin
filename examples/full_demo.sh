#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

tuin_banner "tuin demo"
tuin_section "1. tuin_choose"
fruit=$(tuin_choose "Apple" "Banana" "Cherry" "Date" "Elderberry" \
                    "Fig" "Grape" "Honeydew" "Kiwi" "Lemon" "Mango")
echo "Picked: $fruit"

tuin_section "2. tuin_input"
name=$(tuin_input "Your name" "World")

tuin_section "3. tuin_confirm"
if tuin_confirm "Shall we proceed, $name?" y; then
    tuin_section "4. tuin_spin"
    tuin_spin "Working" -- sleep 2
    tuin_banner "All done, $name!"
else
    echo "Aborted."
fi
