#!/bin/bash
set -e

REPO="staghado/better-live-audio"
INSTALL_DIR="$HOME/.local/share/better-live-audio"

info()  { printf "  \033[1;32m->\033[0m %s\n" "$1"; }
warn()  { printf "  \033[1;33m->\033[0m %s\n" "$1"; }
error() { printf "  \033[1;31m->\033[0m %s\n" "$1"; }

echo ""
echo "  better-live-audio - Local dictation for macOS"
echo ""

[[ "$(uname)" != "Darwin" ]] && error "macOS only" && exit 1

if ! command -v brew &>/dev/null; then
    error "homebrew not found"
    echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi

info "checking dependencies..."
for pkg in llama.cpp sox hammerspoon jq; do
    if brew list "$pkg" &>/dev/null; then
        info "$pkg already installed"
    else
        info "installing $pkg..."
        brew install "$pkg" </dev/null
    fi
done

info "downloading better-live-audio..."
rm -rf "$INSTALL_DIR"
git clone -q "https://github.com/$REPO.git" "$INSTALL_DIR" </dev/null
cd "$INSTALL_DIR"

chmod +x src/better-live-audio/run.sh

HAMMERSPOON_CONFIG="$HOME/.hammerspoon/init.lua"
mkdir -p "$HOME/.hammerspoon"

if grep -q "better-live-audio" "$HAMMERSPOON_CONFIG" 2>/dev/null; then
    warn "hammerspoon config already exists, skipping"
else
    [ -f "$HAMMERSPOON_CONFIG" ] && cp "$HAMMERSPOON_CONFIG" "$HAMMERSPOON_CONFIG.backup.$(date +%s)"

    cat >> "$HAMMERSPOON_CONFIG" << 'LUAEOF'

-- better-live-audio (https://github.com/staghado/better-live-audio)
local blaDir = os.getenv("HOME") .. "/.local/share/better-live-audio"
local blaRecording = false
local blaRecAlert = nil
local alertStyle = {
    strokeWidth = 2,
    strokeColor = { white = 1, alpha = 0.25 },
    fillColor = { white = 0.1, alpha = 0.85 },
    textColor = { white = 1, alpha = 1 },
    textFont = ".AppleSystemUIFont",
    textSize = 24,
    radius = 12,
    atScreenEdge = 0,
    fadeInDuration = 0.1,
    fadeOutDuration = 0.2,
    padding = 20,
}

hs.hotkey.bind({"cmd", "shift"}, "a", function()
    if not blaRecording then
        blaRecording = true
        local s = hs.fnutils.copy(alertStyle)
        s.fillColor = { red = 0.4, green = 0.1, blue = 0.1, alpha = 0.85 }
        blaRecAlert = hs.alert.show("● Recording…  ⌘⇧A to stop", s, 9999)
        hs.task.new(blaDir .. "/src/better-live-audio/run.sh", nil, {"start"}):start()
    else
        blaRecording = false
        if blaRecAlert then hs.alert.closeSpecific(blaRecAlert); blaRecAlert = nil end
        local working = hs.alert.show("⏳ Transcribing…", alertStyle, 9999)
        hs.task.new(blaDir .. "/src/better-live-audio/run.sh", function(code)
            hs.alert.closeSpecific(working)
            if code == 0 then
                hs.eventtap.keyStroke({"cmd"}, "v", 0)
                hs.alert.show("✓ Transcript pasted", alertStyle, 2)
                hs.sound.getByName("Pop"):play()
            else
                local s = hs.fnutils.copy(alertStyle)
                s.fillColor = { red = 0.3, green = 0.1, blue = 0.1, alpha = 0.85 }
                hs.alert.show("✗ Could not transcribe", s, 2)
                hs.sound.getByName("Basso"):play()
            end
        end, {"stop"}):start()
    end
end)
LUAEOF
    info "hammerspoon config added"
fi

pgrep -q "Hammerspoon" || open -a Hammerspoon 2>/dev/null || warn "start Hammerspoon manually"

echo ""
info "better-live-audio installed successfully"
echo ""
echo "  next steps:"
echo "    1. grant Hammerspoon Accessibility AND Microphone access"
echo "       System Settings → Privacy & Security → Accessibility / Microphone"
echo "    2. click Hammerspoon menu bar icon → Reload Config"
echo "    3. Cmd+Shift+A → speak → Cmd+Shift+A → paste"
echo ""
echo "  first run downloads the model (~3 GB). Subsequent runs are fast."
echo ""
