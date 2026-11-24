#!/bin/bash
set -euo pipefail
app=${1:-PipFlow.app}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

python3 - "$fixture/silence.wav" <<'PY'
import sys
import wave

with wave.open(sys.argv[1], "wb") as audio:
    audio.setparams((1, 2, 16_000, 32_000, "NONE", "not compressed"))
    audio.writeframes(bytes(64_000))
PY
env -i "$app/Contents/Helpers/transcribe-cli" -q \
  -m "$app/Contents/Resources/granite-q8.gguf" --threads 2 \
  -o "$fixture/transcript.txt" "$fixture/silence.wav"
test -f "$fixture/transcript.txt"
