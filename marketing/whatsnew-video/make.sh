#!/bin/bash
# The whole piece: audio → master → frames → mux. Output: out/headroom-whats-new-16x9.mp4 (60 fps, CRF 17).
set -euo pipefail
cd "$(dirname "$0")"
export NODE_PATH="${NODE_PATH:-$(npm root -g)}"
node render.mjs audio
./master.sh
node render.mjs video "$@"
ffmpeg -hide_banner -loglevel error -y -i out/frames.mp4 -i out/audio.wav \
  -map 0:v -map 1:a -vf "scale=in_range=pc:out_range=tv,format=yuv420p" -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p \
  -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 -r 60 -profile:v high \
  -c:a aac -b:a 320k -ar 48000 -movflags +faststart -shortest out/headroom-whats-new-16x9.mp4
ffprobe -v error -show_entries format=duration,size -of default=nw=1 out/headroom-whats-new-16x9.mp4
