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

# "thunder" as third argument: only the ThunderRoad command calls (below).
if [[ "$3" != thunder ]]; then
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
fi

# ThunderRoad command calls (ThunderCallsData, data/modes/thunder_calls_sv.tres).
for pair in "cmd_taken tagit-kontroll-förbered-anfall" "cmd_lost tappat-kontroll-omgruppera" \
    "cmd_regrouping De-omgrupperar-förbered-anfall-anmäl-klar" \
    "cmd_enemy_coming fienden-kommer-till-stridsställningar" "cmd_secured zon-säkrad" \
    "cmd_attack_2min anfallare-2-minuter-kvar" "cmd_attack_1min anfallare-1-minut-kvar" \
    "cmd_defend_2min 2-min-kvar-håll-linjen" "cmd_defend_1min en-minut-kvar-håll-ut" \
    "cmd_return återvänd-till-stridsställningar"; do
  set -- $pair
  trim "$S/ElevenLabs_$2.mp3" "$T/$1.wav"
  radio "$1" "$T/$1.wav" -16
done

# "Fall tillbaka till ÅSA <n>!" for checkpoints 1-7: the whole recording (it ends on "ÅSA")
# plus the number cut out of the clock hours ("Klockan tre!" from NUMBER_CUT_S[n], read off
# spectrograms) after a short gap. Move a cut if a number sounds clipped or keeps an "n".
NUMBER_CUT_S=(0 0.41 0.40 0.37 0.39 0.40 0.37 0.36)
trim "$S/ElevenLabs_fall-tillbaka-till-åsa-n.mp3" "$T/fall.wav"
ffmpeg -loglevel error -y -f lavfi -t 0.07 -i "anullsrc=r=22050:cl=mono" "$T/gap7.wav"
for n in $(seq 1 7); do
  ffmpeg -loglevel error -y -i "$S/klockan/klockan_$n.wav" -ss "${NUMBER_CUT_S[n]}" \
    -af "aresample=22050,afade=t=in:d=0.015" -ac 1 "$T/num.wav"
  ffmpeg -loglevel error -y -i "$T/fall.wav" -i "$T/gap7.wav" -i "$T/num.wav" \
    -filter_complex "[0][1][2]concat=n=3:v=0:a=1" "$T/fall_n.wav"
  radio "cmd_fall_back_$n" "$T/fall_n.wav" -16
done

# Banter (ThunderCallsData): the crew at a round's start and the match's end (intercom), rare
# extras from command (radio), the crew's rare HE line (CrewVoiceData.he_dirt).
for pair in "cmd_lost_rare lost-zone-blå-skåpet" "cmd_return_rare lämnar-zon-Larsson-kan-inte-reglementet"; do
  set -- $pair
  trim "$S/ElevenLabs_$2.mp3" "$T/$1.wav"
  radio "$1" "$T/$1.wav" -16
done
for pair in "crew_he he-vilken-jädra-smäll" \
    "crew_start_1 start-då-var-vi-här-då" "crew_start_2 start-Framåt-kamrater" \
    "crew_start_3 start-ge-dom-vad-de-tål" "crew_start_4 start-Jag-har-en-plan" \
    "crew_start_5 start-nu-gäller-det" "crew_start_6 start-uppoffring" \
    "crew_win_1 vinst-bra-jobbat-fika" "crew_win_2 vinst-dans-på-rosor" \
    "crew_win_3 vinst-lätt-som-en-plätt" "crew_win_4 vinst-slipsten" \
    "crew_loss_1 förlust-inte-lätt" "crew_loss_2 förlust-lite-tråkigt" \
    "crew_loss_3 förlust-pipsvängen" "crew_loss_4 förlust-tack-å-gonatt" \
    "crew_loss_5 förlust-tur-med-vädret" "crew_loss_6 förlust-vänder-blad"; do
  set -- $pair
  trim "$S/ElevenLabs_$2.mp3" "$T/$1.wav"
  intercom "$1" "$T/$1.wav" -15
done
# 2026-11-14: the fighting retreat (ThunderCallsData), King of the Hill (KothCallsData), Bot hunt
# (FreeFightCallsData) and kill banter (ModeRadio, CrewVoiceData rare lines). Sources were named
# from their text by tools/audio/transcribe.py (Whisper).
for pair in "cmd_bh_wave_new_1 bh-våg-ny-spaning-rapporterar" "cmd_bh_wave_new_2 bh-våg-ny-fientligt-pansar" \
    "cmd_bh_wave_cleared_1 bh-våg-slagen-fienden-nedkämpad" "cmd_bh_wave_cleared_2 bh-våg-slagen-ladda-om" \
    "cmd_tank_lost vi-har-förlorat-en-vagn" "cmd_koth_open koth-zon-öppen-ny-anfallsorder" \
    "cmd_koth_next koth-zon-nästa-punkt-markerad" "cmd_koth_advantage koth-övertaget" \
    "cmd_koth_outnumbered koth-de-är-fler" "cmd_koth_closing koth-zonen-stänger-snart" \
    "cmd_koth_near_win koth-nära-vinst-lite-till" "cmd_koth_enemy_near_1 koth-fiende-nära-skärpning" \
    "cmd_koth_enemy_near_2 koth-fiende-nära-kom-igen" "cmd_attack_1min_rare 1min-systemet-stänger" \
    "cmd_advance_1 avancera-fienden-retirerar" "cmd_advance_2 avancera-fortsätt-framåt" \
    "cmd_stragglers_1 eftersläntrare-städa-bort" "cmd_stragglers_2 eftersläntrare-markerade" \
    "cmd_next_open_1 nästa-öppen-anfallsorder-nästa-punkt" "cmd_next_open_2 nästa-öppen-nästa-åsa" \
    "cmd_enemy_coming_2 fienden-kommer-alla-redo" "cmd_enemy_coming_3 fienden-kommer-eldställningar"; do
  set -- $pair
  trim "$S/ElevenLabs_$2.mp3" "$T/$1.wav"
  radio "$1" "$T/$1.wav" -16
done
for pair in "crew_alone_1 bh-ensamma-nu-grabbar" "crew_alone_2 bh-ensam-är-stark" \
    "crew_hit_rare träffade-jävlar-jävlar" "crew_mine_rare mina-volvo-240" \
    "crew_kill_1 kill-tjosan" "crew_kill_2 kill-tjosan-2" "crew_kill_3 kill-12-poäng" \
    "crew_kill_zone_1 kill-zon-allemansrätten" "crew_kill_zone_2 kill-zon-parkeringsförbud" \
    "crew_win_5 vinst-klappat-och-klart" "crew_win_6 vinst-en-kaffe" "crew_win_7 vinst-jävligt-lagom" \
    "crew_start_7 start-bara-att-åka" "crew_left_behind_1 kvar-avskurna-backa" \
    "crew_left_behind_2 kvar-bakom-fiendens-linjer" "crew_left_behind_10s kvar-tio-sekunder" \
    "crew_made_it_1 tillbaka-mammas-gata" "crew_made_it_2 tillbaka-puh-nära"; do
  set -- $pair
  trim "$S/ElevenLabs_$2.mp3" "$T/$1.wav"
  intercom "$1" "$T/$1.wav" -15
done
# 2026-11-14: the tutorial instructor (TutorialData, TUTORIAL_PLAN.md) and the crash line
# (CrewVoiceData "Crash"); named from their text by tools/audio/transcribe.py.
for pair in "tut_0_welcome tut-0-välkommen" "tut_1_drive tut-1-kör" "tut_1_done tut-1-klar" \
    "tut_2_open tut-2-öppna" "tut_2_danger tut-2-fara" "tut_2_close tut-2-stäng" \
    "tut_3_binoculars tut-3-kikare" "tut_3_done tut-3-klar" "tut_4_spot tut-4-markera" \
    "tut_5_sight tut-5-sikte" "tut_5_short tut-5-kort" "tut_5_hit tut-5-träff" \
    "tut_6_he tut-6-he" "tut_6_done tut-6-klar" "tut_7_map tut-7-karta" "tut_7_mine tut-7-mina" \
    "tut_7_recall tut-7-hem" "tut_7_done tut-7-klar" "tut_8_under_fire tut-8-beskjuten" \
    "tut_8_done tut-8-klar" "tut_9_test tut-9-prov" "tut_9_done tut-9-klar" \
    "tut_skip tut-hoppar" "tut_restart tut-omstart" "crew_crash_1 crash-rally-kalle"; do
  set -- $pair
  trim "$S/ElevenLabs_$2.mp3" "$T/$1.wav"
  intercom "$1" "$T/$1.wav" -15
done
rm -rf "$T"
