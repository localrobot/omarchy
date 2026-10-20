#!/bin/bash

unit_source="$OMARCHY_PATH/default/systemd/user/llama-server.service"
unit_target="$HOME/.config/systemd/user/llama-server.service"

if [[ -f $unit_source ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  install -Dm644 "$unit_source" "$unit_target"
fi

