#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# The catppuccin-nvim colorscheme name only exists in newer plugin checkouts
# (added upstream in March 2026); catppuccin-mocha loads on old and new ones
# alike, so the stock theme uses the flavour name (#12721).
if matches=$(grep -rn 'catppuccin-nvim' "$ROOT/themes/"); then
  fail "stock themes avoid the newer-only catppuccin colorscheme name" "$matches"
fi
pass "stock themes avoid the newer-only catppuccin colorscheme name"

grep -Fq 'colorscheme = "everforest"' "$ROOT/themes/everforest/neovim.lua" ||
  fail "everforest theme uses its colorscheme"
pass "everforest theme uses its colorscheme"
