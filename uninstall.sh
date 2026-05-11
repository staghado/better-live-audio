#!/bin/bash
info()  { printf "  \033[1;32m->\033[0m %s\n" "$1"; }
warn()  { printf "  \033[1;33m->\033[0m %s\n" "$1"; }

echo ""
echo "  better-live-audio - uninstall"
echo ""

pkill -f "llama-server.*granite-speech" 2>/dev/null || true
rm -rf "$HOME/.local/share/better-live-audio"

info "removed ~/.local/share/better-live-audio"
echo ""
echo "  to complete:"
echo "    1. remove the better-live-audio block from ~/.hammerspoon/init.lua"
echo "    2. optional: brew uninstall llama.cpp sox hammerspoon jq"
echo ""
