#!/bin/bash
# Makes the squad radio calls (Swedish) with Piper TTS and a radio filter:
#   make_radio.sh <piper binary> <voice .onnx> <project>/assets/audio/radio [only]
# [only]: a name pattern (e.g. at_fire) to make just those calls.
# Voice used: sv_SE-nst-medium (rhasspy/piper-voices on Hugging Face; trained by KBLab
# on the NST Swedish dataset, CC0). Piper: pip install piper-tts (in a venv).
set -e
PIPER=$1; VOICE=$2; O=$3; ONLY=${4:-*}; mkdir -p "$O"
T=$(mktemp -d)
NUM=(x ett två tre fyra fem sex sju åtta nio tio elva tolv)
say() { # name text length_scale
  [[ "$1" == $ONLY ]] || return 0
  echo "$2" | "$PIPER" -m "$VOICE" --length-scale "${3:-0.85}" -f "$T/raw.wav" 2>/dev/null
  # Radio: narrow band, squashed and slightly overdriven, a hiss bed, a squelch
  # burst before and after.
  ffmpeg -loglevel error -y -i "$T/raw.wav" \
    -f lavfi -t 0.12 -i "anoisesrc=color=white:amplitude=0.35:r=22050" \
    -f lavfi -t 0.18 -i "anoisesrc=color=white:amplitude=0.35:r=22050" \
    -f lavfi -i "anoisesrc=color=pink:amplitude=0.03:r=22050" \
    -filter_complex "\
[0]aresample=22050,highpass=f=380,lowpass=f=2900,acompressor=threshold=-24dB:ratio=8:attack=3:release=60,volume=6dB,asoftclip=type=tanh,adelay=140:all=1,apad=pad_dur=0.25[v];\
[1]highpass=f=800,lowpass=f=4000,afade=t=out:st=0.06:d=0.06[s1];\
[2]highpass=f=800,lowpass=f=4000,afade=t=in:d=0.02,afade=t=out:st=0.12:d=0.06[s2];\
[v][s1]amix=inputs=2:normalize=0:duration=first[vs];\
[3]highpass=f=500,lowpass=f=3000[hiss];\
[vs][hiss]amix=inputs=2:normalize=0:duration=first[body];\
[body][s2]concat=n=2:v=0:a=1,alimiter=limit=0.9" \
    -ac 1 -c:a libvorbis -q:a 5 "$O/$1.ogg"
}
say under_attack "Vi är under anfall!" 0.8
say returning "Återvänder till vagnen." 0.9
say in_position "I position." 0.9
say at_fire "Skott kommer! Klart bakåt!" 0.8
for h in $(seq 1 12); do
  say "infantry_$h" "Fientliga skyttar, klockan ${NUM[$h]}!" 0.8
  say "armour_$h" "Pansar, klockan ${NUM[$h]}!" 0.8
done
rm -rf "$T"
