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
local blaLiveFile = "/tmp/bla_live.txt"
local blaRecording = false
local blaRecAlert = nil
local blaLiveCanvas = nil
local blaLiveTimer = nil
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

local function blaCreateCanvas()
    local screen = hs.screen.mainScreen():frame()
    local w = math.min(900, screen.w - 80)
    local h = 110
    local x = screen.x + (screen.w - w) / 2
    local y = screen.y + screen.h - h - 80
    blaLiveCanvas = hs.canvas.new({ x = x, y = y, w = w, h = h })
    blaLiveCanvas:appendElements(
        {
            type = "rectangle", action = "fill",
            fillColor = { white = 0.1, alpha = 0.85 },
            strokeColor = { white = 1, alpha = 0.25 },
            strokeWidth = 2,
            roundedRectRadii = { xRadius = 12, yRadius = 12 },
        },
        {
            id = "txt", type = "text", text = "",
            textColor = { white = 1, alpha = 1 },
            textFont = ".AppleSystemUIFont",
            textSize = 20,
            textAlignment = "left",
            frame = { x = 20, y = 16, w = w - 40, h = h - 32 },
        }
    )
    blaLiveCanvas:show()
end

-- Defer materializing the canvas until tokens actually arrive, so the user
-- doesn't stare at an empty box for the first chunk's worth of audio.
local function blaStartLive()
    blaLiveTimer = hs.timer.doEvery(0.1, function()
        local f = io.open(blaLiveFile, "r")
        if not f then return end
        local s = f:read("*a") or ""
        f:close()
        if s == "" then return end
        if not blaLiveCanvas then blaCreateCanvas() end
        if #s > 300 then s = "…" .. s:sub(-300) end
        blaLiveCanvas[2].text = s
    end)
end

local function blaStopLive()
    if blaLiveTimer then blaLiveTimer:stop(); blaLiveTimer = nil end
    if blaLiveCanvas then blaLiveCanvas:delete(); blaLiveCanvas = nil end
end

hs.hotkey.bind({"cmd", "shift"}, "a", function()
    if not blaRecording then
        blaRecording = true
        -- Pre-truncate to hide any stale text before run.sh races in to clear it.
        local f = io.open(blaLiveFile, "w"); if f then f:close() end
        blaStartLive()
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
            blaStopLive()
            if code == 0 then
                hs.alert.show("✓ Transcript copied", alertStyle, 2)
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
