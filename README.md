# better-live-audio

⌘⇧A, speak, ⌘⇧A, paste.

Local dictation for macOS. [Granite Speech 4.0 1B](https://huggingface.co/ibm-granite/granite-4.0-1b-speech) via [llama.cpp](https://github.com/ggml-org/llama.cpp).

## Installation
```bash
curl -LsSf https://raw.githubusercontent.com/staghado/better-live-audio/main/install.sh | sh
```

Then:
1. Grant Hammerspoon Accessibility and Microphone access (System Settings, Privacy & Security).
2. Click Hammerspoon menu bar icon, Reload Config.

## Usage

Press ⌘⇧A to start, press ⌘⇧A again to stop. Transcript copies to the clipboard. Paste with ⌘V.

First run downloads the model (~3 GB). Subsequent runs hit the warm server.

## Configuration

Edit `HF_REPO` and `CHUNK_SEC` at the top of [`src/better-live-audio/run.sh`](src/better-live-audio/run.sh). Restart the server with `pkill -f "llama-server.*granite-speech"` to apply.

## Uninstall
```bash
curl -LsSf https://raw.githubusercontent.com/staghado/better-live-audio/main/uninstall.sh | sh
```

## Requirements

- macOS (Apple Silicon)
- [Homebrew](https://brew.sh)

The installer adds:
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [sox](https://sox.sourceforge.net/)
- [Hammerspoon](https://www.hammerspoon.org/)
- [jq](https://jqlang.github.io/jq/)

## How it Works

`rec` records 16 kHz mono WAV in 30-second chunks. A worker transcribes each chunk as soon as the next one starts, in parallel with the ongoing recording. On stop, the last chunk is finalized and any backlog is drained, then chunk transcripts are joined and copied.

## Credits

- [Granite Speech 4.0 1B](https://huggingface.co/ibm-granite/granite-4.0-1b-speech) (IBM). [GGUF conversion](https://huggingface.co/staghado/granite-speech-4.0-1b-GGUF).
- [llama.cpp](https://github.com/ggml-org/llama.cpp). Granite Speech support: [@ReinforcedKnowledge](https://github.com/ReinforcedKnowledge), [#22101](https://github.com/ggml-org/llama.cpp/pull/22101).
- [Hammerspoon](https://www.hammerspoon.org/).
- Inspired by [better-live-text](https://github.com/staghado/better-live-text).

## License

MIT
