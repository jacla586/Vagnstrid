"""A first trailer cut from the recorded takes and the title cards.

  geodata/.venv/bin/python -I tools/trailer/make_cut.py [--preview]

Reads renders/trailer/<take>.mp4 and renders/trailer/cards/*.png (make_cards.py), writes
renders/trailer/cut/vagnstrid_trailer_v3.mp4 (1080p60; --preview: 640x360, fast) via one
intermediate file per segment. Times are seconds in each take's film (its cue list).
A card plays over the given stretch of a take, dimmed and blurred, the take's sound low.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TAKES = os.path.join(ROOT, "renders", "trailer")
CARDS = os.path.join(TAKES, "cards")
OUT = os.path.join(TAKES, "cut")

# (take, start, end[, opts]) for footage (opts: "duck_at" = film time after which the take's
# sound drops, "notch" = (from, to) film times where the voice band is cut out of the take's
# sound, "mix" = [(sound file, film time, volume)] laid over it); ("CARD", card, take, start, end) for a card over a take;
# ("TITLE", take, start, end) for the end title.
EDIT = [
    ("advance", 3.5, 8.3),                      # the line on Vallastaden, HE in the field
    ("CARD", "01_fc_helt_okej", "advance", 8.3, 10.8),
    # The AT gunner rises, "Skott kommer! Klart bakåt!", the round, "Vi är träffade!", then the
    # squad's "Träff!" (not in the take: the enemy squad's radio) over the take ducked.
    ("ambush", 15.0, 22.35, {"duck_at": 20.8, "mix": [("assets/audio/radio/at_hit.ogg", 20.85, 0.6)]}),
    # HE into the smoke; the take's scream (wilhelm_3) filtered out, wilhelm_2 laid in.
    ("ambush", 29.0, 33.0, {"notch": (30.75, 31.85), "mix": [("assets/audio/voice/wilhelm_2.ogg", 30.85, 0.55)]}),
    ("CARD", "02_sz_ai_slop", "ambush", 33.0, 35.5),
    ("smoke", 6.5, 15.3),                       # kills 1 and 2 in the sight, near miss, smoke, backing in
    ("smoke", 23.6, 28.4),                      # kills 3 and 4
    ("CARD", "07_fc_flaskhals", "smoke", 28.4, 30.9),
    ("playground_cam-chase", 10.5, 15.0),       # the playground goes
    ("CARD", "04_fc_lunchrast", "playground_cam-chase", 15.0, 17.5),
    ("kv2_plow", 4.8, 14.5),                    # firing from straight above, the crane: a field of wrecks
    ("kv2_plow", 22.4, 27.0),                   # the KV-2 ploughs through, ping
    ("CARD", "08_forum_pling", "kv2_plow", 27.0, 29.0),
    ("kv2_plow", 29.0, 33.0),                   # the turret flies
    ("CARD", "05_sz_tornen", "kv2_plow", 33.0, 35.0),
    ("turret_toss_toss-20", 6.8, 13.0),         # 152 mm, slow motion, the turret goes
    ("CARD", "09_sz_nastan_bra", "turret_toss_toss-20", 13.0, 15.5),
    ("opening", 31.6, 34.8),                    # a kill in the gunner's sight
    ("CARD", "06_forum_asikt", "opening", 34.8, 37.3),
    ("kv2_plow", 36.1, 38.8),                   # HE in the KV-2's track
    ("kv2_plow", 42.9, 47.5),                   # from behind: the KV-2's turret goes
    ("CARD", "13_sz_tva_av_fem", "kv2_plow", 47.5, 50.0),
    ("CARD", "11_forum_last", "column_cam-drone", 14.0, 16.5),
    ("TITLE", "advance_cam-drone", 4.5, 10.5),   # film times include the 3.3 s black load
]
FALLBACK = {"advance_cam-drone": ("column_cam-drone", 12.0, 18.0), "advance": ("column", 8.0, 12.5)}   # until they exist
FADE = 0.04


def ffmpeg(args: list[str]) -> None:
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)


def title_png(path: str) -> None:
    w, h = 1920, 1080
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    big = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", 190)
    small = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf", 46)
    t1, t2 = "VAGNSTRID", "Stridsvagnar. Skyttegrupper. Pling."
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for dd, fill in ((sd, (0, 0, 0, 200)), (d, None)):
        x1 = (w - d.textlength(t1, font=big)) / 2
        x2 = (w - d.textlength(t2, font=small)) / 2
        if fill:
            dd.text((x1 + 6, 380 + 8), t1, font=big, fill=fill)
            dd.text((x2 + 3, 620 + 4), t2, font=small, fill=fill)
        else:
            dd.text((x1, 380), t1, font=big, fill=(245, 245, 240, 255))
            dd.text((x2, 620), t2, font=small, fill=(236, 112, 26, 255))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    shadow.alpha_composite(im)
    shadow.save(path)


def main() -> None:
    preview = "--preview" in sys.argv
    size = "640:360" if preview else "1920:1080"
    venc = ["-c:v", "libx264", "-preset", "ultrafast" if preview else "medium", "-crf", "28" if preview else "16",
            "-pix_fmt", "yuv420p", "-r", "60"]
    aenc = ["-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"]
    os.makedirs(OUT, exist_ok=True)
    title = os.path.join(OUT, "title.png")
    title_png(title)
    parts: list[str] = []
    total = 0.0
    for n, seg in enumerate(EDIT):
        kind = seg[0]
        out = os.path.join(OUT, f"part{n:02d}.mp4")
        if kind in ("CARD", "TITLE"):
            png = title if kind == "TITLE" else os.path.join(CARDS, seg[1] + ".png")
            take, a, b = seg[-3:]
        else:
            png = None
            take, a, b = seg[:3]
        opts: dict = seg[3] if png is None and len(seg) > 3 else {}
        if not os.path.exists(os.path.join(TAKES, take + ".mp4")) and take in FALLBACK:
            take, a, b = FALLBACK[take]
        src = os.path.join(TAKES, take + ".mp4")
        dur = b - a
        if png is None and opts:
            mixes = opts.get("mix", [])
            take_af = ""
            if "duck_at" in opts:
                take_af += f"volume='if(lt(t,{opts['duck_at'] - a}),1,0.2)':eval=frame,"
            if "notch" in opts:
                n0, n1 = opts["notch"][0] - a, opts["notch"][1] - a
                for f in (900, 1400, 2100, 3000):
                    take_af += f"equalizer=f={f}:t=o:w=0.8:g=-20:enable='between(t,{n0},{n1})',"
            fc = f"[0:v]scale={size},fade=in:st=0:d={FADE}[v];[0:a]{take_af}anull[ta];"
            ins = ["-ss", str(a), "-t", str(dur), "-i", src]
            labels = "[ta]"
            for k, (mix_file, mix_at, mix_vol) in enumerate(mixes):
                ms = int((mix_at - a) * 1000)
                ins += ["-i", os.path.join(ROOT, mix_file)]
                fc += f"[{k + 1}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={ms}|{ms},volume={mix_vol}[m{k}];"
                labels += f"[m{k}]"
            fc += (f"{labels}amix=inputs={len(mixes) + 1}:normalize=0:duration=first,"
                   f"afade=in:st=0:d={FADE},afade=out:st={dur - FADE}:d={FADE}[a]")
            ffmpeg(ins + ["-filter_complex", fc, "-map", "[v]", "-map", "[a]"] + venc + aenc + [out])
        elif png is None:
            vf = f"scale={size},fade=in:st=0:d={FADE}"
            ffmpeg(["-ss", str(a), "-t", str(dur), "-i", src, "-vf", vf,
                    "-af", f"afade=in:st=0:d={FADE},afade=out:st={dur - FADE}:d={FADE}"] + venc + aenc + [out])
        else:
            dim = "eq=brightness=-0.12:saturation=0.7,gblur=sigma=5" if kind == "CARD" else "eq=brightness=-0.05"
            fade_out = f",fade=out:st={dur - 1.2}:d=1.2" if kind == "TITLE" else ""
            vol = "0.45" if kind == "CARD" else "0.8"
            afo = f"afade=out:st={dur - 1.5}:d=1.5" if kind == "TITLE" else f"afade=out:st={dur - FADE}:d={FADE}"
            fc = (f"[0:v]scale={size},{dim}[bg];"
                  f"[1:v]scale={size},format=rgba,fade=in:st=0:d=0.25:alpha=1[card];"
                  f"[bg][card]overlay=0:0:shortest=1{fade_out}[v];"
                  f"[0:a]volume={vol},afade=in:st=0:d={FADE},{afo}[a]")
            ffmpeg(["-ss", str(a), "-t", str(dur), "-i", src, "-loop", "1", "-t", str(dur), "-i", png,
                    "-filter_complex", fc, "-map", "[v]", "-map", "[a]"] + venc + aenc + [out])
        parts.append(out)
        total += dur
        print(f"{n:2d}  {total:5.1f} s  {seg}")
    lst = os.path.join(OUT, "parts.txt")
    with open(lst, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    final = os.path.join(OUT, "vagnstrid_trailer_v3_preview.mp4" if preview else "vagnstrid_trailer_v3.mp4")
    ffmpeg(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", "-movflags", "+faststart", final])
    for p in parts:
        os.remove(p)
    os.remove(lst)
    print(f"-> {final}  ({total:.1f} s)")


if __name__ == "__main__":
    main()
