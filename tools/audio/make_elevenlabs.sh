#!/bin/bash
# Makes the game's voice calls from the ElevenLabs recordings (Swedish):
#   make_elevenlabs.sh <source dir, e.g. geodata/sound> <project>/assets/audio/radio
# Same filters as make_radio.sh (squad radio: narrow band, hiss, squelch; crew intercom:
# wider band, engine rumble) but no pitching or drive: the recordings already sound
# stressed. ElevenLabs_klockan.mp3 ("Klockan ett!" ... "Klockan tolv!", pauses between)
# is cut at its pauses into <source>/klockan/klockan_<h>.wav; the contact calls are
# "Pansar!" / "Skyttar!" followed by the hour.
set -e
S=$1; O=$2; mkdir -p "$O" "$S/klockan"
T=$(mktemp -d)

# trim <in> <out>: cut silence at both ends, keep 30 ms.
trim() {
  ffmpeg -loglevel error -y -i "$1" -af "\
silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,areverse,\
silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,areverse,\
aresample=22050" -ac 1 "$2"
}

# radio <name> <source wav> <loudness LUFS>
radio() {
  ffmpeg -loglevel error -y -i "$2" \
    -f lavfi -t 0.12 -i "anoisesrc=color=white:amplitude=0.35:r=22050" \
    -f lavfi -t 0.18 -i "anoisesrc=color=white:amplitude=0.35:r=22050" \
    -f lavfi -i "anoisesrc=color=pink:amplitude=0.03:r=22050" \
    -filter_complex "\
[0]aresample=22050,highpass=f=380,lowpass=f=2900,asoftclip=type=tanh,adelay=140:all=1,apad=pad_dur=0.25[v];\
[1]highpass=f=800,lowpass=f=4000,afade=t=out:st=0.06:d=0.06[s1];\
[2]highpass=f=800,lowpass=f=4000,afade=t=in:d=0.02,afade=t=out:st=0.12:d=0.06[s2];\
[v][s1]amix=inputs=2:normalize=0:duration=first[vs];\
[3]highpass=f=500,lowpass=f=3000[hiss];\
[vs][hiss]amix=inputs=2:normalize=0:duration=first[body];\
[body][s2]concat=n=2:v=0:a=1,loudnorm=I=$3:TP=-1:LRA=7,aresample=22050,alimiter=limit=0.9" \
    -ac 1 -c:a libvorbis -q:a 5 "$O/$1.ogg"
}

# intercom <name> <source wav> <loudness LUFS>
intercom() {
  ffmpeg -loglevel error -y -i "$2" \
    -f lavfi -i "anoisesrc=color=brown:amplitude=0.06:r=22050" \
    -filter_complex "\
[0]aresample=22050,highpass=f=250,lowpass=f=3800,asoftclip=type=tanh,adelay=40:all=1,apad=pad_dur=0.15[v];\
[1]lowpass=f=400[rumble];\
[v][rumble]amix=inputs=2:normalize=0:duration=first,loudnorm=I=$3:TP=-1:LRA=7,aresample=22050,alimiter=limit=0.9" \
    -ac 1 -c:a libvorbis -q:a 5 "$O/$1.ogg"
}

# Cut the clock hours at the pauses (silence >= 0.25 s): 12 parts expected.
K="$S/ElevenLabs_klockan.mp3"
LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$K")
mapfile -t EDGES < <(ffmpeg -hide_banner -i "$K" -af silencedetect=noise=-40dB:d=0.25 -f null - 2>&1 \
  | grep -oE "silence_(start|end): [0-9.]+" | awk '{print $2}')
STARTS=(0); ENDS=()
for ((i = 0; i < ${#EDGES[@]}; i += 2)); do
  ENDS+=("${EDGES[i]}")
  [[ -n "${EDGES[i+1]}" ]] && STARTS+=("${EDGES[i+1]}")
done
(( ${#ENDS[@]} < ${#STARTS[@]} )) && ENDS+=("$LEN")
if (( ${#STARTS[@]} != 12 )); then
  echo "klockan: found ${#STARTS[@]} parts, expected 12" >&2; exit 1
fi
for h in $(seq 1 12); do
  ffmpeg -loglevel error -y -i "$K" -ss "${STARTS[h-1]}" -to "${ENDS[h-1]}" "$T/k.wav"
  trim "$T/k.wav" "$S/klockan/klockan_$h.wav"
done

for n in under-anfall avsittning uppsittning på-plats skott-kommer träff miss pansar skyttar träffade närträff föraren-träffad skytten-träffad vagnchef-träffad mina-band-utslaget upprättar-minering mina-armerad mina-utlöst; do
  trim "$S/ElevenLabs_$n.mp3" "$T/$n.wav"
done
trim "$S/ElevenLabs_Närskydd.mp3" "$T/närskydd.wav"
ffmpeg -loglevel error -y -f lavfi -t 0.12 -i "anullsrc=r=22050:cl=mono" "$T/gap.wav"

radio under_attack "$T/under-anfall.wav" -16
radio dismount "$T/avsittning.wav" -18
radio returning "$T/uppsittning.wav" -18
radio escort "$T/närskydd.wav" -18
radio in_position "$T/på-plats.wav" -18
radio at_fire "$T/skott-kommer.wav" -13
radio at_hit "$T/träff.wav" -14
radio at_miss "$T/miss.wav" -14
radio mine_laying "$T/upprättar-minering.wav" -18
radio mine_armed "$T/mina-armerad.wav" -18
radio mine_triggered "$T/mina-utlöst.wav" -15
for h in $(seq 1 12); do
  for pair in "armour pansar" "infantry skyttar"; do
    set -- $pair
    ffmpeg -loglevel error -y -i "$T/$2.wav" -i "$T/gap.wav" -i "$S/klockan/klockan_$h.wav" \
      -filter_complex "[0][1][2]concat=n=3:v=0:a=1" "$T/call.wav"
    radio "$1_$h" "$T/call.wav" -16
  done
done
intercom crew_hit "$T/träffade.wav" -13
intercom crew_near_miss "$T/närträff.wav" -16
intercom crew_driver_hit "$T/föraren-träffad.wav" -14
intercom crew_gunner_hit "$T/skytten-träffad.wav" -14
intercom crew_commander_hit "$T/vagnchef-träffad.wav" -14
intercom crew_mine "$T/mina-band-utslaget.wav" -13
rm -rf "$T"
