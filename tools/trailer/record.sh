#!/usr/bin/env bash
# Records a trailer shot to renders/trailer/<shot>[_<tag>].mp4 (1080p60, with sound).
#   tools/trailer/record.sh <shot> [key=value ...]     e.g. opening weather=dawn
# Frames go to renders/trailer/<name>_frames/ (PNG + WAV), then ffmpeg makes a high
# quality MP4 and the PNGs are deleted (keep=1 keeps them). Needs a window (not headless).
# Without a film: add snap=1 and a JPG lands in renders/trailer/snaps/ at every cue.
set -euo pipefail
cd "$(dirname "$0")/../.."
shot="$1"; shift
tag=""
keep=0
args=()
for a in "$@"; do
  case "$a" in
    keep=1) keep=1 ;;
    *) args+=("$a"); tag="${tag}_${a//=/-}" ;;
  esac
done
name="${shot}${tag}"
frames="renders/trailer/${name}_frames"
rm -rf "$frames"; mkdir -p "$frames"
# Movie Maker films at the project's window size (1152x648), whatever --resolution says:
# a temporary override.cfg makes the window 1920x1080 for this run only.
if [ -e override.cfg ]; then echo "override.cfg exists already; not touching it" >&2; exit 1; fi
trap 'rm -f override.cfg' EXIT
printf '[display]\n\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n' > override.cfg
godot --path . --disable-vsync --fixed-fps 60 \
  --write-movie "$frames/frame.png" \
  --script res://tools/trailer/trailer.gd -- "$shot" "out=$frames" "${args[@]}"
ffmpeg -y -loglevel error -framerate 60 -i "$frames/frame%08d.png" -i "$frames/frame.wav" \
  -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -c:a aac -b:a 256k -shortest \
  "renders/trailer/${name}.mp4"
rm -f override.cfg
cp "$frames/cues.txt" "renders/trailer/${name}_cues.txt" 2>/dev/null || true
[ "$keep" = 1 ] || rm -f "$frames"/frame*.png
echo "-> renders/trailer/${name}.mp4"
