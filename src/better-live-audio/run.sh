#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin"

SERVER_URL="http://localhost:8081"
CONTEXT_SIZE=4096   # Granite Speech 4.0 1B's trained ceiling — don't raise

HF_REPO="staghado/granite-speech-4.0-1b-GGUF"
TRANSCRIBE_PROMPT="can you transcribe the speech into a written format?"

CHUNK_SEC=30
SESSION_DIR="${TMPDIR:-/tmp}/bla_session"
TRANSCRIPTS="$SESSION_DIR/transcripts.txt"
LIVE_FILE="/tmp/bla_live.txt"   # fixed path so the Hammerspoon overlay can find it
REC_PIDFILE="${TMPDIR:-/tmp}/bla_rec.pid"
WORKER_PIDFILE="${TMPDIR:-/tmp}/bla_worker.pid"

server_ready() {
    curl -sf --max-time 1 "$SERVER_URL/health" >/dev/null 2>&1
}

ensure_server() {
    server_ready && return
    llama-server -hf "$HF_REPO" -c "$CONTEXT_SIZE" --port 8081 \
        --jinja --temp 0 --top-k 1 \
        >"${TMPDIR:-/tmp}/llama-server-audio.log" 2>&1 &
    for _ in $(seq 240); do
        server_ready && return
        sleep 0.5
    done
    exit 1
}

transcribe_chunk() {
    local wav="$1"
    [ -s "$wav" ] || return 1
    # base64 + jq via files to avoid ARG_MAX (25 s of audio ≈ 1 MB base64)
    local b64="${wav}.b64" json="${wav}.json"
    base64 -i "$wav" | tr -d '\n' > "$b64"
    jq -n --rawfile aud "$b64" --arg prompt "$TRANSCRIBE_PROMPT" '{
        stream: true,
        messages: [{role: "user", content: [
            {type: "input_audio", input_audio: {data: $aud, format: "wav"}},
            {type: "text", text: $prompt}
        ]}]
    }' > "$json"
    # tee streams tokens to LIVE_FILE for the live overlay; the captured stdout
    # is the joined chunk text used for the final clipboard paste.
    local result
    result=$(
        curl -sfN --max-time 120 "$SERVER_URL/v1/chat/completions" \
            -H "Content-Type: application/json" --data-binary "@$json" \
        | jq --unbuffered -j -R '
              if startswith("data: [DONE]") then empty
              elif startswith("data: ") then
                  (.[6:] | fromjson? | .choices[0].delta.content // empty)
              else empty end' \
        | tee -a "$LIVE_FILE"
    ) || { rm -f "$b64" "$json"; return 1; }
    rm -f "$b64" "$json"
    [ -n "$result" ] && printf ' ' >> "$LIVE_FILE"
    printf '%s\n' "$result" | awk 'NF'
}

case "${1:-}" in
    start)
        rm -rf "$SESSION_DIR"; mkdir -p "$SESSION_DIR"
        : > "$TRANSCRIPTS"
        : > "$LIVE_FILE"

        # Recorder: rec records CHUNK_SEC, exits (WAV header finalized), loop spawns the next one.
        # .stop sentinel signals the loop to halt; SIGINT to the in-flight rec finalizes its chunk.
        nohup bash -c '
            i=0
            while [ ! -f "'"$SESSION_DIR"'/.stop" ]; do
                chunk=$(printf "'"$SESSION_DIR"'/chunk_%03d.wav" $i)
                rec -q -c 1 -r 16000 -b 16 "$chunk" trim 0 '"$CHUNK_SEC"' \
                    </dev/null >/dev/null 2>&1 || true
                [ -s "$chunk" ] || break
                i=$((i+1))
            done
        ' </dev/null >/dev/null 2>&1 &
        echo $! > "$REC_PIDFILE"

        # Worker: transcribes chunks in order, in parallel with recording
        nohup "$0" _worker </dev/null >/dev/null 2>&1 &
        echo $! > "$WORKER_PIDFILE"
        ;;

    stop)
        [ -f "$REC_PIDFILE" ] || exit 0
        rec_wrapper=$(cat "$REC_PIDFILE"); rm -f "$REC_PIDFILE"

        touch "$SESSION_DIR/.stop"
        pkill -INT -P "$rec_wrapper" 2>/dev/null || true
        for _ in $(seq 50); do kill -0 "$rec_wrapper" 2>/dev/null || break; sleep 0.1; done
        kill -KILL "$rec_wrapper" 2>/dev/null || true

        touch "$SESSION_DIR/.done"

        if [ -f "$WORKER_PIDFILE" ]; then
            worker=$(cat "$WORKER_PIDFILE"); rm -f "$WORKER_PIDFILE"
            # Wait up to ~3 min for worker to drain backlog
            for _ in $(seq 1800); do kill -0 "$worker" 2>/dev/null || break; sleep 0.1; done
            kill -KILL "$worker" 2>/dev/null || true
        fi

        text=$(awk 'NF' "$TRANSCRIPTS" 2>/dev/null | paste -sd ' ' - | sed -e 's/[[:space:]]\{2,\}/ /g' -e 's/^ *//' -e 's/ *$//')
        rm -rf "$SESSION_DIR"
        [ -z "$text" ] && exit 1
        printf '%s' "$text" | pbcopy
        ;;

    _worker)
        ensure_server
        i=0
        while true; do
            chunk=$(printf "$SESSION_DIR/chunk_%03d.wav" "$i")
            next=$(printf "$SESSION_DIR/chunk_%03d.wav" "$((i+1))")
            # Wait until: next chunk exists (current is complete), OR .done is set
            until [ -e "$next" ] || [ -e "$SESSION_DIR/.done" ]; do
                sleep 0.2
            done
            # No chunk for this index and recording is done → nothing left to do
            [ -e "$chunk" ] || exit 0
            transcribe_chunk "$chunk" >> "$TRANSCRIPTS" || true
            echo >> "$TRANSCRIPTS"
            i=$((i+1))
        done
        ;;

    *) exit 2 ;;
esac
