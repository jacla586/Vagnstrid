# Sound credits

All sounds are **CC0** (public domain), from [Freesound](https://freesound.org). Attribution is not
required, but we list the authors anyway. Files were cut, looped, mixed to mono and normalised (shots and blasts also compressed for punch) with
`tools/audio/process_sounds.sh` (sources downloaded as Freesound HQ previews with
`tools/audio/fetch_freesound.sh`, which checks the licence on each page).

| File | Source (Freesound id – title – author) |
|---|---|
| engine/engine_idle.ogg | [182793](https://freesound.org/s/182793/) – Military Vehicle Humming – qubodup |
| engine/engine_drive.ogg | [186934](https://freesound.org/s/186934/) – engine4_loop – ReadeOnly |
| engine/tracks.ogg | [329800](https://freesound.org/s/329800/) – t26_moving_01 – greatmganga |
| cannon/cannon_fire_1.ogg | [127845](https://freesound.org/s/127845/) – Tank fire Mixed – GaryQ |
| cannon/cannon_fire_2.ogg | [702245](https://freesound.org/s/702245/) – 69th Field Artillery Gun 01 – InMotionAudio |
| cannon/cannon_distant_1.ogg | [517747](https://freesound.org/s/517747/) – Distant Explosion – danlucaz |
| cannon/cannon_distant_2.ogg | [324277](https://freesound.org/s/324277/) – distant explosion – Kostrava |
| explosion/he_1.ogg | [231765](https://freesound.org/s/231765/) – Tank Explosion – unfa |
| explosion/he_2.ogg | [476225](https://freesound.org/s/476225/) – Huge Distant Explosion – Fission9 |
| impact/ricochet_1.ogg | [345413](https://freesound.org/s/345413/) – Bullet_Ricochet_01 – Artmasterrich |
| impact/ricochet_2–3.ogg | [675955](https://freesound.org/s/675955/) – S20-02 Rifle ricochets – craigsmith |
| impact/ricochet_4.ogg | [478345](https://freesound.org/s/478345/) – Bullet Ricochet 1_3 – Joao_Janz |
| impact/armour_hit_1–3.ogg | [675951](https://freesound.org/s/675951/) – S31-15 Shooting gallery; hitting metal targets – craigsmith |
| impact/armour_thud_1.ogg | [640204](https://freesound.org/s/640204/) – Heavy Metal Thud on Ground – 7of9Designs |
| mg/mg_shot_1–2.ogg | [482122](https://freesound.org/s/482122/) – Clean Machine Gun Burst – qubodup |
| explosion/impact_distant_1–4.ogg | [455513](https://freesound.org/s/455513/) – Distant Blasts – DylanTheFish |
| impact/ap_ground_1–3.ogg | Kenney `impactSoft_heavy_000–002` mixed with the start of [231765](https://freesound.org/s/231765/) (unfa) |
| hatch/hatch_open.ogg | [718445](https://freesound.org/s/718445/) – Metal_Hatch_Small_Open_03 – Rudmer_Rotteveel |
| hatch/hatch_close.ogg | [488221](https://freesound.org/s/488221/) – Opening and closing a small metal hatch – Irolan |
| voice/wilhelm_1–4.ogg | [813303](https://freesound.org/s/813303/)–[813306](https://freesound.org/s/813306/) – Wilhelm Scream Alternative 1–4 – qubodup (imitations, not the Warner Bros original) |
| impact/ping.ogg | Made for this project (CC0): synthesised with `tools/audio/make_ping.py` |
| impact/kenney/*.ogg | [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) 1.0 – Kenney (CC0, `License.txt` alongside): `impactPlate_heavy`, `impactMetal_heavy`, `impactMetal_light`, `impactSoft_heavy` (mixed to mono, normalised) |

## Squad radio (`radio/`)
Spoken with Piper TTS (https://github.com/rhasspy/piper) using the voice
`sv_SE-nst-medium` (trained by KBLab, National Library of Sweden, on the NST Swedish
dataset, CC0), then radio-filtered with ffmpeg: `tools/audio/make_radio.sh`.

## ElevenLabs voices
Some voice lines are generated with [ElevenLabs](https://elevenlabs.io) (text to speech,
free plan). Free-plan terms: attribution to elevenlabs.io is required and the audio may
only be used non-commercially.

Voices from elevenlabs.io.

| File | Voice | Line |
|---|---|---|
| *(to be filled in when the files are added)* | | |
