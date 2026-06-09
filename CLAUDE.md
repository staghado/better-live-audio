# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS-only local dictation tool. Three Bash scripts, no build step, no tests. ⌘⇧A toggles recording via a Hammerspoon hotkey; on stop, the transcript is copied to the clipboard *and* auto-pasted into the focused text field via a synthesized ⌘V.

**Intended use case: short prompts (5–30 s) dictated into coding agents.** Not long-form dictation or live captioning. This shapes scope decisions — don't propose VAD-driven chunking, per-word streaming, or live overlays; the stop-triggered single-decode path is already fast for short utterances and the user has explicitly declined those directions.

## Commands

- Install locally: `./install.sh` (clones into `~/.local/share/better-live-audio`, appends a block to `~/.hammerspoon/init.lua`, `brew install`s deps).
- Uninstall: `./uninstall.sh` (kills the llama-server, removes the install dir; Hammerspoon block must be removed by hand).
- Restart the model server after editing `HF_REPO` or other server flags: `pkill -f "llama-server.*granite-speech"` — `ensure_server` in `run.sh` will relaunch it on the next `start`.
- Drive the pipeline manually without Hammerspoon: `src/better-live-audio/run.sh start` then `src/better-live-audio/run.sh stop`.
- Tail the model server log: `tail -f "${TMPDIR:-/tmp}/llama-server-audio.log"`.

When iterating on `install.sh`, note the installer does `rm -rf "$INSTALL_DIR"` and `git clone` from GitHub — it will not pick up uncommitted local changes. Test by running `run.sh` directly out of this checkout, or push first.

## Architecture

The whole pipeline lives in `src/better-live-audio/run.sh`, which is a single script dispatching on `$1` (`start` / `stop` / `_worker`). Hammerspoon (configured by `install.sh`) calls it with `start` and `stop`.

Three cooperating processes per session, coordinated through files in `$SESSION_DIR` (`${TMPDIR}/bla_session`):

1. **Recorder loop** (backgrounded from `start`): repeatedly invokes `rec` (sox) for `CHUNK_SEC` seconds, writing `chunk_000.wav`, `chunk_001.wav`, … Each `rec` invocation exits cleanly so the WAV header is finalized before the next chunk begins. PID stored in `$REC_PIDFILE`.
2. **Worker** (`_worker` subcommand, backgrounded from `start`): runs `ensure_server` to lazy-start `llama-server` against `$HF_REPO` on port 8127 (default; override with `BLA_PORT`), then walks `chunk_NNN.wav` in order, POSTing each as base64 audio to `/v1/chat/completions` and appending the result to `$TRANSCRIPTS`. PID in `$WORKER_PIDFILE`.
3. **llama-server**: persistent background process; survives across recording sessions so the model stays warm. Killed only by `uninstall.sh` or manually.

`stop` signals the recorder via `.stop` sentinel + `SIGINT` to the in-flight `rec` (which finalizes the current chunk), waits for the worker to drain the backlog (up to ~3 min), then joins `$TRANSCRIPTS` with `awk`/`paste` and pipes to `pbcopy`.

### Synchronization invariants

- The worker decides "current chunk is complete" by waiting for `chunk_NNN+1.wav` to *exist* — that means `rec` has rotated. The `.done` sentinel covers the tail case where no further chunk will ever appear.
- `transcribe_chunk` writes base64 + JSON to temp files because a 25-second WAV produces ~1 MB of base64, which would blow past `ARG_MAX` if passed inline to `jq` / `curl`.
- `CONTEXT_SIZE=4096` is Granite Speech 4.0 1B's trained ceiling — don't raise it; the comment in `run.sh` is load-bearing.
- `CHUNK_SEC` (default 30) is a **ceiling**, not a fixed window. For the typical 5–30 s prompt, `stop` SIGINTs `rec` mid-chunk and the chunk is finalized at whatever length the user has actually spoken — so there's exactly one decode pass per session. Don't reduce it to chase latency; you'd only hurt accuracy on the rare long utterance.

### Hammerspoon binding

The `init.lua` block written by `install.sh` is the only UI: ⌘⇧A toggles between calling `run.sh start` and `run.sh stop`, shows alert overlays during recording/transcribing, plays Pop/Basso on success/failure, and on success synthesizes ⌘V via `hs.eventtap.keyStroke` so the transcript pastes itself into the focused field. If you change the script's CLI surface, update the installer's heredoc to match — there is no version negotiation between them. Users who already installed must replace the block in `~/.hammerspoon/init.lua` by hand and Reload Config; `install.sh` only writes the block on first install.
