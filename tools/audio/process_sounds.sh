#!/bin/bash
# Run from the folder holding raw/<id>/<id>.mp3 (made by fetch_freesound.sh): process_sounds.sh <project>/assets/audio
# Cuts, mono-mixes, peak-normalises and encodes sounds to ogg for the game.
set -e
R=raw; O=$1; mkdir -p $O/engine $O/cannon $O/explosion $O/impact $O/mg $O/hatch $O/voice
calc() { awk "BEGIN{print $1}"; }
norm() { # in out
  local g=$(ffmpeg -nostats -i "$1" -af volumedetect -f null - 2>&1 | grep -o 'max_volume: [-0-9.]*' | awk '{print -1 - $2}')
  ffmpeg -loglevel error -y -i "$1" -af "volume=${g}dB" -ac 1 -c:a libvorbis -q:a 5 "$2"
}
cut() { # id start end out [fade_out_s]
  local f=${5:-0.05}; local d=$(calc "$3 - $2")
  # -ss before -i: the cut starts at t=0, so the fades are timed from the cut's start.
  ffmpeg -loglevel error -y -ss $2 -i $R/$1/$1.mp3 -t $d -ac 1 \
    -af "afade=t=in:d=0.005,afade=t=out:st=$(calc "$d - $f"):d=$f" tmp.wav
  norm tmp.wav "$4"
}
loop() { # id start len xfade out
  local S=$2 L=$3 F=$4
  ffmpeg -loglevel error -y -i $R/$1/$1.mp3 -filter_complex \
   "[0]aformat=channel_layouts=mono,asplit[s1][s2];[s1]atrim=$(calc "$S + $F"):$(calc "$S + $F + $L"),asetpts=PTS-STARTPTS,afade=t=out:st=$(calc "$L - $F"):d=$F[b];[s2]atrim=$S:$(calc "$S + $F"),asetpts=PTS-STARTPTS,afade=t=in:d=$F,adelay=$(calc "($L - $F) * 1000"):all=1[a];[b][a]amix=inputs=2:normalize=0:duration=first" tmp.wav
  norm tmp.wav "$5"
}
loop 182793 5 10 1 $O/engine/engine_idle.ogg
loop 186934 0.5 10 1 $O/engine/engine_drive.ogg
loop 329800 2 10 1 $O/engine/tracks.ogg
cut 127845 0 1.3 $O/cannon/cannon_fire_1.ogg 0.7
cut 702245 0 1.0 $O/cannon/cannon_fire_2.ogg 0.5
cut 517747 0.29 1.75 $O/cannon/cannon_distant_1.ogg 0.3
cut 324277 0 5.3 $O/cannon/cannon_distant_2.ogg 1.0
cut 231765 0 4.0 $O/explosion/he_1.ogg 1.5
cut 476225 0 6.0 $O/explosion/he_2.ogg 2.0
cut 345413 0 0.70 $O/impact/ricochet_1.ogg 0.1
cut 675955 0 1.35 $O/impact/ricochet_2.ogg 0.3
cut 675955 1.78 3.27 $O/impact/ricochet_3.ogg 0.3
cut 478345 0 3.49 $O/impact/ricochet_4.ogg 0.8
cut 675951 0.36 1.20 $O/impact/armour_hit_1.ogg 0.2
cut 675951 1.62 3.46 $O/impact/armour_hit_2.ogg 0.5
cut 675951 5.35 7.03 $O/impact/armour_hit_3.ogg 0.4
cut 640204 0 0.78 $O/impact/armour_thud_1.ogg 0.1
cut 718445 0.31 1.52 $O/hatch/hatch_open.ogg 0.2
cut 488221 0.75 1.55 $O/hatch/hatch_close.ogg 0.1
for i in 1 2 3 4; do cut 81330$((i+2)) 0 $(ffprobe -v error -show_entries format=duration -of csv=p=0 $R/81330$((i+2))/81330$((i+2)).mp3) $O/voice/wilhelm_$i.ogg 0.05; done
rm -f tmp.wav

# --- Second pass (2026-11-04): single MG shots, distant impacts, AP ground impact ---
# MG: single shots with their natural tail (the shot before a pause in each burst).
cut 482122 0.905 1.16 $O/mg/mg_shot_1.ogg 0.12
cut 482122 1.340 1.60 $O/mg/mg_shot_2.ogg 0.12


# Distant blasts: a shell landing far away (not the same as a distant cannon).
cut 455513 2.20 4.80 $O/explosion/impact_distant_1.ogg 0.8
cut 455513 47.30 49.95 $O/explosion/impact_distant_2.ogg 0.8
cut 455513 131.07 133.60 $O/explosion/impact_distant_3.ogg 0.8
cut 455513 170.95 172.90 $O/explosion/impact_distant_4.ogg 0.6
# AP shell into the ground: Kenney's dull thud layered on the start of a blast.
K=$O/impact/kenney
for i in 0 1 2; do
  ffmpeg -loglevel error -y -i $K/impactSoft_heavy_00$i.ogg -i $R/231765/231765.mp3 -filter_complex \
    "[1]aformat=channel_layouts=mono,atrim=0:1.4,asetpts=PTS-STARTPTS,asetrate=48000*1.25,aresample=48000,volume=-7dB,afade=t=out:st=0.5:d=0.6[b];[0]aformat=channel_layouts=mono,aresample=48000[a];[a][b]amix=inputs=2:normalize=0:duration=longest" tmp.wav
  norm tmp.wav $O/impact/ap_ground_$((i+1)).ogg
done
rm -f tmp.wav

# --- Third pass (2026-11-04): punch. Short shots and blasts are compressed and lifted so
# they cut through the engine loops (fun over realism). Run after the passes above.
punch() { # file: compress, limit, peak-normalise in place
  ffmpeg -loglevel error -y -i "$1" -af "acompressor=threshold=-30dB:ratio=6:attack=2:release=150:makeup=4,alimiter=limit=0.95:attack=1:release=50" tmp.wav
  norm tmp.wav "$1"
}
for f in $O/explosion/*.ogg $O/cannon/*.ogg $O/mg/*.ogg $O/impact/ap_ground_*.ogg; do punch "$f"; done
rm -f tmp.wav
