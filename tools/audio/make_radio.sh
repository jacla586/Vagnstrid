#!/bin/bash
# Makes the squad radio calls and the crew's intercom calls (Swedish) with Piper TTS:
#   make_radio.sh <piper binary> <voice .onnx> <project>/assets/audio/radio [only]
# [only]: a name pattern (e.g. at_fire) to make just those calls.
# Voice used: sv_SE-nst-medium (rhasspy/piper-voices on Hugging Face; trained by KBLab
# on the NST Swedish dataset, CC0). Piper: pip install piper-tts (in a venv).
# Combat voice: spoken fast with a lively generator, then pitched up (a raised, pressed
# voice) and driven hard; "stress" 1 = calm report, 2 = urgent, 3 = shouted.
set -e
PIPER=$1; VOICE=$2; O=$3; ONLY=${4:-*}; mkdir -p "$O"
T=$(mktemp -d)
NUM=(x ett två tre fyra fem sex sju åtta nio tio elva tolv)

# voice <text> <length_scale> <stress> -> $T/voice.wav (22.05 kHz, pitched, driven);
# sets LOUD, the loudness the finished call is brought to (LUFS): shouts are loudest.
voice() {
  local pitch gain noise
  case $3 in
    3) pitch=1.17; gain=13; noise=0.95; LOUD=-13 ;;
    2) pitch=1.09; gain=9;  noise=0.85; LOUD=-16 ;;
    *) pitch=1.04; gain=7;  noise=0.75; LOUD=-18 ;;
  esac
  echo "$1" | "$PIPER" -m "$VOICE" --length-scale "$2" --noise-scale $noise --noise-w-scale 0.9 \
    -f "$T/raw.wav" 2>/dev/null
  # Pitch up without changing the pace: play faster, then stretch back.
  ffmpeg -loglevel error -y -i "$T/raw.wav" -af "\
asetrate=22050*$pitch,aresample=22050,atempo=1/$pitch,\
acompressor=threshold=-28dB:ratio=10:attack=2:release=50,volume=${gain}dB,asoftclip=type=tanh" \
    "$T/voice.wav"
}

# radio <name> <text> <length_scale> <stress>: the squad's radio (narrow band, hiss,
# squelch before and after).
radio() {
  [[ "$1" == $ONLY ]] || return 0
  voice "$2" "$3" "$4"
  ffmpeg -loglevel error -y -i "$T/voice.wav" \
    -f lavfi -t 0.12 -i "anoisesrc=color=white:amplitude=0.35:r=22050" \
    -f lavfi -t 0.18 -i "anoisesrc=color=white:amplitude=0.35:r=22050" \
    -f lavfi -i "anoisesrc=color=pink:amplitude=0.03:r=22050" \
    -filter_complex "\
[0]highpass=f=380,lowpass=f=2900,asoftclip=type=tanh,adelay=140:all=1,apad=pad_dur=0.25[v];\
[1]highpass=f=800,lowpass=f=4000,afade=t=out:st=0.06:d=0.06[s1];\
[2]highpass=f=800,lowpass=f=4000,afade=t=in:d=0.02,afade=t=out:st=0.12:d=0.06[s2];\
[v][s1]amix=inputs=2:normalize=0:duration=first[vs];\
[3]highpass=f=500,lowpass=f=3000[hiss];\
[vs][hiss]amix=inputs=2:normalize=0:duration=first[body];\
[body][s2]concat=n=2:v=0:a=1,loudnorm=I=$LOUD:TP=-1:LRA=7,aresample=22050,alimiter=limit=0.9" \
    -ac 1 -c:a libvorbis -q:a 5 "$O/$1.ogg"
}

# intercom <name> <text> <length_scale> <stress>: a crewman on the tank's intercom
# (wider band than the radio, engine rumble, no squelch).
intercom() {
  [[ "$1" == $ONLY ]] || return 0
  voice "$2" "$3" "$4"
  ffmpeg -loglevel error -y -i "$T/voice.wav" \
    -f lavfi -i "anoisesrc=color=brown:amplitude=0.06:r=22050" \
    -filter_complex "\
[0]highpass=f=250,lowpass=f=3800,asoftclip=type=tanh,adelay=40:all=1,apad=pad_dur=0.15[v];\
[1]lowpass=f=400[rumble];\
[v][rumble]amix=inputs=2:normalize=0:duration=first,loudnorm=I=$LOUD:TP=-1:LRA=7,aresample=22050,alimiter=limit=0.9" \
    -ac 1 -c:a libvorbis -q:a 5 "$O/$1.ogg"
}

radio under_attack "Vi är under anfall!" 0.72 2
radio returning "Återvänder till vagnen!" 0.8 1
radio in_position "I position!" 0.8 1
radio at_fire "Skott kommer! Klart bakåt!" 0.62 3
for h in $(seq 1 12); do
  radio "infantry_$h" "Fientliga skyttar, klockan ${NUM[$h]}!" 0.74 2
  radio "armour_$h" "Pansar, klockan ${NUM[$h]}!" 0.74 2
done
intercom crew_hit "Vi är träffade!" 0.62 3
intercom crew_near_miss "Närträff!" 0.68 2
rm -rf "$T"
