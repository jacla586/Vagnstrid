"""Trailer title cards: made-up "reviews" from parody outlets, drawn as clippings.

  geodata/.venv/bin/python -I tools/trailer/make_cards.py [background.jpg]

Writes transparent 1920x1080 PNGs to renders/trailer/cards/ (lay them over the film in the
edit) and previews over a background picture (default: a trailer snap) plus a contact sheet.
Three kinds: a tech news page (FragClockers), a game site's review (SweZone) and a forum
post. The outlets are parodies: own names and looks, no real logos.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "renders", "trailer", "cards")
W, H = 1920, 1080
FONT_DIR = "/usr/share/fonts/truetype/noto/"


def font(style: str, size: int) -> ImageFont.FreeTypeFont:
    if style == "Symbol":   # stars: Noto Sans has no ★
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", size)
    style = "Bold" if style == "Black" else style   # no Black weight installed
    for name in (f"NotoSans-{style}.ttf", "NotoSans-Regular.ttf"):
        path = os.path.join(FONT_DIR, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    for para in text.split("\n"):
        line = ""
        for word in para.split(" "):
            test = (line + " " + word).strip()
            if draw.textlength(test, font=f) <= width or not line:
                line = test
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def text_block(draw, xy, text, f, fill, width, gap=1.18) -> int:
    """Draws wrapped text; returns the y below it."""
    x, y = xy
    for line in wrap(draw, text, f, width):
        draw.text((x, y), line, font=f, fill=fill)
        y += int(f.size * gap)
    return y


def place(card: Image.Image, tilt: float = 0.0) -> Image.Image:
    """Puts a card in the middle of a transparent frame with a soft shadow."""
    if tilt:
        card = card.rotate(tilt, resample=Image.BICUBIC, expand=True)
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = (W - card.width) // 2
    y = (H - card.height) // 2
    alpha = card.split()[3].point(lambda a: int(a * 0.55))
    shadow.paste((0, 0, 0, 255), (x + 14, y + 22), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    frame.alpha_composite(shadow)
    frame.alpha_composite(card, (x, y))
    return frame


def rounded(size, radius, fill) -> Image.Image:
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=fill)
    return im


# --- FragClockers: a tech news page --------------------------------------------------

ORANGE = (236, 112, 26)


def fragclockers(headline: str, lead: str, comments: int, time: str, tag: str = "SPEL") -> Image.Image:
    cw = 1240
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    fh, fl = font("Bold", 64), font("Regular", 31)
    body_h = 64 + len(wrap(probe, headline, fh, cw - 120)) * 76 + 26 \
        + len(wrap(probe, lead, fl, cw - 120)) * 37 + 120
    ch = 92 + body_h
    card = rounded((cw, ch), 10, (255, 255, 255, 255))
    d = ImageDraw.Draw(card)
    # Top bar: wordmark (a clock dial for the O) and the menu.
    d.rounded_rectangle((0, 0, cw - 1, 92), 10, fill=ORANGE)
    d.rectangle((0, 60, cw - 1, 92), fill=ORANGE)
    fw = font("Black", 42)
    d.text((40, 20), "FRAGCL", font=fw, fill="white")
    ox = 40 + d.textlength("FRAGCL", font=fw) + 2
    d.ellipse((ox, 27, ox + 34, 61), outline="white", width=6)
    d.line((ox + 17, 44, ox + 17, 33), fill="white", width=4)
    d.line((ox + 17, 44, ox + 26, 44), fill="white", width=4)
    d.text((ox + 40, 20), "CKERS", font=fw, fill="white")
    fm = font("Bold", 24)
    mx = cw - 40
    for item in reversed(["Nyheter", "Tester", "Forum", "Marknad", "Logga in"]):
        mx -= d.textlength(item, font=fm)
        d.text((mx, 33), item, font=fm, fill=(255, 240, 225))
        mx -= 36
    # Body.
    y = 92 + 40
    ft = font("Bold", 22)
    tw = d.textlength(tag, font=ft)
    d.rounded_rectangle((60, y, 60 + tw + 24, y + 36), 4, fill=ORANGE)
    d.text((72, y + 4), tag, font=ft, fill="white")
    y += 58
    y = text_block(d, (60, y), headline, fh, (25, 25, 28), cw - 120, 1.18) + 14
    y = text_block(d, (60, y), lead, fl, (85, 85, 92), cw - 120, 1.2) + 22
    d.line((60, y, cw - 60, y), fill=(225, 225, 228), width=2)
    fb = font("Regular", 24)
    d.text((60, y + 18), f"Av Redaktionen  ·  {time}", font=fb, fill=(130, 130, 138))
    c = f"{comments} kommentarer"
    cx = cw - 60 - d.textlength(c, font=fb)
    d.rounded_rectangle((cx - 44, y + 16, cx - 14, y + 40), 6, fill=ORANGE)
    d.polygon([(cx - 36, y + 40), (cx - 28, y + 40), (cx - 38, y + 48)], fill=ORANGE)
    d.text((cx, y + 18), c, font=fb, fill=ORANGE)
    return card


# --- SweZone: a game site's review ---------------------------------------------------

RED = (214, 32, 39)


def swezone(headline: str, lead: str, score: str, score_note: str, kind: str = "RECENSION") -> Image.Image:
    cw = 1260
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    fh, fl = font("Black", 66), font("Regular", 31)
    text_w = cw - 120 - 260
    body_h = 70 + len(wrap(probe, headline, fh, text_w)) * 80 + 20 + len(wrap(probe, lead, fl, text_w)) * 38 + 70
    ch = max(84 + body_h, 84 + 380)
    card = rounded((cw, ch), 6, (20, 21, 24, 255))
    d = ImageDraw.Draw(card)
    d.rectangle((0, 0, cw - 1, 84), fill=(12, 12, 14))
    d.rectangle((0, 80, cw - 1, 84), fill=RED)
    fw = font("Black", 44)
    d.text((40, 14), "SWE", font=fw, fill="white")
    d.text((40 + d.textlength("SWE", font=fw), 14), "ZONE", font=fw, fill=RED)
    fm = font("Bold", 23)
    mx = cw - 40
    for item in reversed(["Nyheter", "Recensioner", "Video", "Forum"]):
        mx -= d.textlength(item, font=fm)
        d.text((mx, 28), item.upper(), font=fm, fill=(190, 190, 196))
        mx -= 34
    y = 84 + 40
    ft = font("Black", 22)
    d.rectangle((60, y, 60 + d.textlength(kind, font=ft) + 26, y + 36), fill=RED)
    d.text((73, y + 4), kind, font=ft, fill="white")
    y += 62
    y = text_block(d, (60, y), headline, fh, (245, 245, 248), text_w, 1.2) + 10
    text_block(d, (60, y), lead, fl, (170, 170, 178), text_w, 1.22)
    # The score.
    sx, sy, sr = cw - 60 - 200, 84 + 70, 200
    d.ellipse((sx, sy, sx + sr, sy + sr), outline=RED, width=12)
    fs = font("Symbol" if "★" in score else "Black", 76 if len(score) <= 4 else 50)
    sw = d.textlength(score, font=fs)
    d.text((sx + (sr - sw) / 2, sy + sr / 2 - fs.size * 0.68), score, font=fs, fill="white")
    fn = font("Bold", 24)
    for i, line in enumerate(wrap(d, score_note, fn, 240)):
        nw = d.textlength(line, font=fn)
        d.text((sx + (sr - nw) / 2, sy + sr + 18 + i * 30), line, font=fn, fill=(200, 200, 206))
    return card


# --- Forum post ----------------------------------------------------------------------

def forum(user: str, rank: str, posts: int, when: str, text: str, quote: tuple[str, str] | None = None,
          likes: int = 0, avatar_colour=(90, 110, 140), moderator: bool = False) -> Image.Image:
    cw = 1220
    side = 250
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    ft = font("Regular", 38)
    tw = cw - side - 80
    qh = 0
    if quote:
        qh = 70 + len(wrap(probe, quote[1], font("Italic", 29), tw - 50)) * 36 + 30
    th = len(wrap(probe, text, ft, tw)) * 48
    ch = max(60 + 30 + qh + th + 100, 330)
    card = rounded((cw, ch), 8, (246, 246, 248, 255))
    d = ImageDraw.Draw(card)
    # Header strip.
    d.rounded_rectangle((0, 0, cw - 1, 52), 8, fill=(222, 224, 230))
    d.rectangle((0, 30, cw - 1, 52), fill=(222, 224, 230))
    fs = font("Regular", 22)
    crumbs = "Forum  ›  Spel  ›  Vagnstrid – diskussionstråd"
    d.text((24, 13), crumbs, font=font("Bold", 22), fill=(60, 70, 100))
    num = f"{when}   #{posts * 7 % 97 + 2}"
    d.text((cw - 24 - d.textlength(num, font=fs), 13), num, font=fs, fill=(100, 100, 110))
    # User column.
    d.rectangle((0, 52, side, ch - 1), fill=(236, 237, 241))
    ax, ay = (side - 120) // 2, 80
    d.rounded_rectangle((ax, ay, ax + 120, ay + 120), 14, fill=avatar_colour)
    fa = font("Black", 52)
    ini = "".join(w[0] for w in user.replace("_", " ").replace("-", " ").split()[:2]).upper()
    iw = d.textlength(ini, font=fa)
    d.text((ax + (120 - iw) / 2, ay + 24), ini, font=fa, fill="white")
    size = 27
    while font("Bold", size).getlength(user) > side - 24 and size > 14:
        size -= 1
    fu = font("Bold", size)
    uw = d.textlength(user, font=fu)
    d.text(((side - uw) / 2, ay + 136), user, font=fu, fill=(200, 60, 20) if moderator else (40, 70, 140))
    fr = font("Regular", 21)
    for i, line in enumerate([rank, f"{posts} inlägg"]):
        lw = d.textlength(line, font=fr)
        d.text(((side - lw) / 2, ay + 176 + i * 28), line, font=fr, fill=(110, 110, 120))
    # The post.
    x, y = side + 40, 52 + 34
    if quote:
        fq = font("Italic", 29)
        lines = wrap(d, quote[1], fq, tw - 50)
        qh2 = 60 + len(lines) * 36 + 10
        d.rectangle((x, y, x + tw, y + qh2), fill=(232, 233, 238))
        d.rectangle((x, y, x + 6, y + qh2), fill=(150, 160, 185))
        d.text((x + 26, y + 14), f"{quote[0]} skrev:", font=font("Bold", 24), fill=(80, 80, 95))
        for i, line in enumerate(lines):
            d.text((x + 26, y + 52 + i * 36), line, font=fq, fill=(70, 70, 80))
        y += qh2 + 26
    y = text_block(d, (x, y), text, ft, (30, 30, 34), tw, 1.26)
    # Footer.
    fb = font("Bold", 22)
    fy = ch - 54
    d.line((x, fy - 14, cw - 40, fy - 14), fill=(220, 220, 226), width=2)
    bx = x
    for label in ["Gilla", "Citera", "Svara"]:
        d.text((bx, fy), label, font=fb, fill=(110, 115, 130))
        bx += d.textlength(label, font=fb) + 34
    if likes:
        lk = f"+{likes}"
        d.text((cw - 40 - d.textlength(lk, font=fb), fy), lk, font=fb, fill=(40, 140, 70))
    return card


CARDS = [
    ("01_fc_helt_okej", lambda: fragclockers(
        "Vagnstrid testad: Helt okej",
        "Vi har spenderat en hel lunchrast med det svenska stridsvagnsspelet. Slutsatsen är tydlig: det är ett spel.",
        347, "idag 12:04"), -1.2),
    ("02_sz_ai_slop", lambda: swezone(
        "Helt okej för att vara AI-slop",
        "Utvecklaren skrev ”kör på” väldigt många gånger. Det märks. Ibland positivt.",
        "7/10", "Kanske 6. Okej, 7."), 1.0),
    ("03_forum_kalla", lambda: forum(
        "Pansarpelle", "Nykomling", 2, "Idag 03:12",
        "Var är källan på att KV-2 var så tung?", likes=0, avatar_colour=(120, 130, 70)), -0.8),
    ("04_fc_lunchrast", lambda: fragclockers(
        "”Bästa spelet jag spelat denna lunchrast”",
        "Läsarna har röstat. Det var en av två röster.",
        89, "igår 12:58", "LÄSARTEST"), 0.9),
    ("05_sz_tornen", lambda: swezone(
        "Tornen flyger längre än mina förväntningar",
        "Vagnstrid gör ett tappert försök. Fysiken är realistisk, enligt någon.",
        "★★★", "(ungefär)"), -1.0),
    ("06_forum_asikt", lambda: forum(
        "Tangentbordsgeneral", "Veteran", 18432, "Idag 09:41",
        "Har inte spelat det men har en åsikt.",
        quote=("Spelglädje_85", "Har någon testat Vagnstrid? Verkar ju rätt kul ändå?"),
        likes=241, avatar_colour=(150, 60, 60)), 0.7),
    ("07_fc_flaskhals", lambda: fragclockers(
        "Vagnstrid flaskhalsar inte RTX 4090",
        "Det gör i och för sig inget annat heller. Vi körde också på en bärbar dator från 2014. Den lever fortfarande.",
        1204, "idag 08:15", "PRESTANDA"), -0.7),
    ("08_forum_pling", lambda: forum(
        "KV-2", "Tung användare", 1, "Idag 14:22",
        "Pling.", likes=3, avatar_colour=(70, 80, 60)), 1.1),
    ("09_sz_nastan_bra", lambda: swezone(
        "Nästan bra",
        "Jag hade inte så tråkigt. Min sambo frågade vad jag höll på med. Jag svarade.",
        "Ja.", "Betyg"), 0.8),
    ("10_forum_rgb", lambda: forum(
        "Klockarn", "Överklockare", 6650, "Igår 23:58",
        "Hade jag haft RGB hade det lyst.", likes=17, avatar_colour=(80, 60, 160)), -1.1),
    ("11_forum_last", lambda: forum(
        "Moderator_Mats", "Moderator", 40211, "Idag 15:03",
        "Tråden låses. Ni har fått pling på hjärnan. Allihop.",
        likes=88, avatar_colour=(200, 90, 30), moderator=True), 0.6),
    ("12_forum_bump", lambda: forum(
        "Trådnekromantikern", "Arkeolog", 913, "2031-04-01 04:04",
        "Bump.", likes=1, avatar_colour=(60, 120, 120)), -0.9),
    ("13_sz_tva_av_fem", lambda: swezone(
        "Två av fem *pling*",
        "Vår gästrecensent KV-2 har tagit emot nio skott från två T-34:or och har några synpunkter.",
        "2/5", "– KV-2, gästrecensent", "GÄSTRECENSION"), -0.6),
]


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    bg_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, "renders", "trailer", "snaps", "kv2_plow_12.00_auto.jpg")
    bg = None
    if os.path.exists(bg_path):
        bg = Image.open(bg_path).convert("RGBA").resize((W, H))
        bg = Image.alpha_composite(bg, Image.new("RGBA", (W, H), (0, 0, 0, 90)))
    previews = []
    for name, make, tilt in CARDS:
        frame = place(make(), tilt)
        frame.save(os.path.join(OUT, name + ".png"))
        if bg is not None:
            pv = Image.alpha_composite(bg, frame).convert("RGB")
            pv.save(os.path.join(OUT, "preview_" + name + ".jpg"), quality=88)
            previews.append(pv)
    if previews:
        cols, tw, th = 3, 640, 360
        sheet = Image.new("RGB", (cols * tw, ((len(previews) + cols - 1) // cols) * th))
        for i, pv in enumerate(previews):
            sheet.paste(pv.resize((tw, th)), ((i % cols) * tw, (i // cols) * th))
        sheet.save(os.path.join(OUT, "sheet.jpg"), quality=85)
    print(f"{len(CARDS)} cards -> {OUT}")


if __name__ == "__main__":
    main()
