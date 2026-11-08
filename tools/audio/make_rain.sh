#!/bin/bash
# Makes the rain loops from noise (CC0 by construction):
#   make_rain.sh <project>/assets/audio/weather
# rain_outside.ogg: steady rain on fields and leaves (pink hiss, a low wash, sparse
# drop ticks). rain_roof.ogg: rain drumming on the turret roof heard from inside
# (velvet-noise impulses through a metallic band and a short ring).
set -e
O=$1; mkdir -p "$O"
D=12
ffmpeg -loglevel error -y \
  -f lavfi -t $D -i "anoisesrc=color=pink:amplitude=0.5:r=44100:seed=7" \
  -f lavfi -t $D -i "anoisesrc=color=brown:amplitude=0.5:r=44100:seed=11" \
  -f lavfi -t $D -i "anoisesrc=color=velvet:amplitude=0.9:density=0.02:r=44100:seed=5" \
  -filter_complex "\
[0]highpass=f=500,lowpass=f=9000,volume=0.8[hiss];\
[1]lowpass=f=600,volume=0.5[wash];\
[2]highpass=f=1500,lowpass=f=7000,volume=0.6[ticks];\
[hiss][wash][ticks]amix=inputs=3:normalize=0,loudnorm=I=-20:TP=-2,afade=t=in:d=0.05,areverse,afade=t=in:d=0.05,areverse" \
  -ac 1 -c:a libvorbis -q:a 4 "$O/rain_outside.ogg"
ffmpeg -loglevel error -y \
  -f lavfi -t $D -i "anoisesrc=color=velvet:amplitude=1.0:density=0.06:r=44100:seed=3" \
  -f lavfi -t $D -i "anoisesrc=color=brown:amplitude=0.4:r=44100:seed=9" \
  -filter_complex "\
[0]bandpass=f=1800:width_type=q:w=1.2,aecho=0.6:0.5:7|13:0.35|0.2,volume=1.5[drum];\
[1]lowpass=f=300,volume=0.4[rumble];\
[drum][rumble]amix=inputs=2:normalize=0,loudnorm=I=-20:TP=-2,afade=t=in:d=0.05,areverse,afade=t=in:d=0.05,areverse" \
  -ac 1 -c:a libvorbis -q:a 4 "$O/rain_roof.ogg"
