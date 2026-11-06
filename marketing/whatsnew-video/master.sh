#!/bin/bash
# Masters out/audio-raw.wav to out/audio.wav: gentle glue compression, a limiter, then two-pass loudnorm to
# -14 LUFS integrated / -1.2 dBTP. (Not the Web Audio compressor: its automatic make-up gain squashes the mix.)
set -euo pipefail
cd "$(dirname "$0")"
in=out/audio-raw.wav
chain="acompressor=threshold=-20dB:ratio=2.2:attack=20:release=200:makeup=1.5,alimiter=limit=0.9:attack=4:release=80:level=false"
stats=$(ffmpeg -hide_banner -nostats -i "$in" -af "$chain,loudnorm=I=-14:TP=-2.0:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
get() { echo "$stats" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
ffmpeg -hide_banner -loglevel error -y -i "$in" -af "$chain,loudnorm=I=-14:TP=-2.0:LRA=11:measured_I=$(get input_i):measured_TP=$(get input_tp):measured_LRA=$(get input_lra):measured_thresh=$(get input_thresh):offset=$(get target_offset):linear=true,aresample=48000" \
  -c:a pcm_s24le out/audio.wav
ffmpeg -hide_banner -nostats -i out/audio.wav -af ebur128=peak=true -f null - 2>&1 | grep -E 'I:|Peak:|LRA:' | tail -3
