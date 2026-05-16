#!/bin/bash
# Resolve the peon-wezterm-hud install directory.
# Sourced by all scripts. Uses HUD_DIR env var if set, otherwise resolves from script location.
if [ -z "${HUD_DIR:-}" ]; then
  HUD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
