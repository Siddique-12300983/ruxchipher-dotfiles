"""Render ruxchipher brand assets: shield logo, GDM logo, UKI splash, Plymouth theme images."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

OUT = Path(sys.argv[1])
WALL = sys.argv[2]
OUT.mkdir(parents=True, exist_ok=True)
FONT = '/usr/share/fonts/TTF/JetBrainsMonoNerdFont-{}.ttf'

BG = (26, 27, 38)
CYAN, BLUE, PURPLE = (125, 207, 255), (122, 162, 247), (187, 154, 247)
FG, SUB, MUTED, GREEN = (192, 202, 245), (169, 177, 214), (86, 95, 137), (158, 206, 106)


def font(style, size):
    return ImageFont.truetype(FONT.format(style), size)


def gradient(w, h, c0, c1, diagonal=True):
    g = Image.new('RGB', (w, h))
    px = g.load()
    for yy in range(h):
        for xx in range(w):
            t = ((xx / max(w - 1, 1)) * 0.65 + (yy / max(h - 1, 1)) * 0.35) if diagonal else xx / max(w - 1, 1)
            px[xx, yy] = tuple(round(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return g


def fast_gradient(w, h, c0, c1):
    """Horizontal gradient built from a 1px row (fast for big images)."""
    row = gradient(256, 1, c0, c1, diagonal=False).resize((w, 1), Image.BILINEAR)
    return row.resize((w, h), Image.NEAREST)


def shield_points(s, inset=0.0):
    def q(p0, p1, p2, n=40):
        return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                 (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]
    i = inset
    right = [(0.5, 0.04 + i), (0.89 - i, 0.17 + i * 0.6), (0.89 - i, 0.50)] + q((0.89 - i, 0.50), (0.87 - i, 0.80), (0.5, 0.96 - i))[1:]
    left = [(1 - x, y) for x, y in reversed(right[1:-1])]
    return [(x * s, y * s) for x, y in right + left]


def shield(size, solid=True, glow=True):
    S = size * 4                                     # supersample
    pad = S // 6 if glow else 0
    canvas = Image.new('RGBA', (S + 2 * pad, S + 2 * pad), (0, 0, 0, 0))
    off = lambda pts: [(x + pad, y + pad) for x, y in pts]
    outer = off(shield_points(S))
    grad = gradient(64, 64, CYAN, PURPLE).resize(canvas.size, Image.BILINEAR)

    stroke = Image.new('L', canvas.size, 0)
    ImageDraw.Draw(stroke).line(outer + outer[:2], fill=255, width=int(S * 0.045), joint='curve')

    if glow:
        halo = stroke.filter(ImageFilter.GaussianBlur(S * 0.05))
        halo = halo.point(lambda v: int(v * 0.9))
        canvas.paste(grad, (0, 0), halo)

    if solid:
        body = Image.new('L', canvas.size, 0)
        ImageDraw.Draw(body).polygon(outer, fill=235)
        canvas.paste(Image.new('RGB', canvas.size, BG), (0, 0), body)

    inner = off(shield_points(S, inset=0.07))
    ring = Image.new('L', canvas.size, 0)
    ImageDraw.Draw(ring).line(inner + inner[:2], fill=90, width=int(S * 0.012), joint='curve')
    canvas.paste(grad, (0, 0), ring)
    canvas.paste(grad, (0, 0), stroke)

    # terminal prompt glyph
    g = Image.new('L', canvas.size, 0)
    f = font('ExtraBold', int(S * 0.30))
    d = ImageDraw.Draw(g)
    text = '❯_'
    bb = d.textbbox((0, 0), text, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text((pad + (S - tw) / 2 - bb[0], pad + S * 0.47 - th / 2 - bb[1]), text, font=f, fill=255)
    canvas.paste(grad, (0, 0), g)

    w = (S + 2 * pad) // 4
    return canvas.resize((w, w), Image.LANCZOS)


def text_img(text, style, size, color=None, grad_colors=None, spacing=0):
    f = font(style, size)
    probe = ImageDraw.Draw(Image.new('L', (1, 1)))
    if spacing:
        widths = [probe.textlength(ch, font=f) for ch in text]
        w = int(sum(widths) + spacing * (len(text) - 1)) + 8
    else:
        w = int(probe.textlength(text, font=f)) + 8
    asc, desc = f.getmetrics()
    h = asc + desc + 8
    mask = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(mask)
    if spacing:
        x = 4
        for ch, cw in zip(text, widths):
            d.text((x, 4), ch, font=f, fill=255)
            x += cw + spacing
    else:
        d.text((4, 4), text, font=f, fill=255)
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    fill = fast_gradient(w, h, *grad_colors) if grad_colors else Image.new('RGB', (w, h), color)
    out.paste(fill, (0, 0), mask)
    return out


# ---------------------------------------------------------------- shared logo
logo = shield(512)
logo.save(OUT / 'shield.png')
shield(128).save(OUT / 'shield-128.png')

# ---------------------------------------------------------------- GDM logo: shield + wordmark
mark = shield(120, glow=False)
word = text_img('ruxchipher', 'Bold', 64, grad_colors=(CYAN, PURPLE))
gdm = Image.new('RGBA', (mark.width + 24 + word.width, max(mark.height, word.height)), (0, 0, 0, 0))
gdm.paste(mark, (0, (gdm.height - mark.height) // 2), mark)
gdm.paste(word, (mark.width + 24, (gdm.height - word.height) // 2), word)
gdm.save(OUT / 'gdm-logo.png')

# ---------------------------------------------------------------- UKI splash (shown by systemd-stub on black)
sp = Image.new('RGB', (360, 360), (0, 0, 0))
s = shield(260)
s_bg = Image.new('RGBA', s.size, (0, 0, 0, 255))
s_bg.alpha_composite(s)
sp.paste(s_bg.convert('RGB'), ((360 - s.width) // 2, (360 - s.height) // 2))
sp.save(OUT / 'splash.bmp')

# ---------------------------------------------------------------- Plymouth theme images
ply = OUT / 'plymouth'
ply.mkdir(exist_ok=True)
logo.resize((300, 300), Image.LANCZOS).save(ply / 'shield.png')

wall = Image.open(WALL).convert('RGB').resize((1920, 1080), Image.LANCZOS)
wall = Image.blend(wall, Image.new('RGB', wall.size, (8, 9, 14)), 0.55)
wall.save(ply / 'bg.png')

text_img('ABU BAKAR SIDDIQUE', 'ExtraBold', 46, grad_colors=(CYAN, PURPLE), spacing=6).save(ply / 'name.png')
# codename types itself out: type0.png .. type10.png are "❯ " + the first k letters
CODENAME = 'ruxchipher'
full = text_img('❯ ' + CODENAME, 'Bold', 26, grad_colors=(CYAN, PURPLE), spacing=4)
for k in range(len(CODENAME) + 1):
    # reveal the finished gradient line up to k letters, so each letter keeps its final colour
    part_w = text_img('❯ ' + CODENAME[:k], 'Bold', 26, color=FG, spacing=4).width - 4
    frame = Image.new('RGBA', (full.width + 24, full.height), (0, 0, 0, 0))   # fixed size: the line never shifts
    frame.paste(full.crop((0, 0, part_w, full.height)), (0, 0))
    if k == len(CODENAME):
        frame.save(ply / 'type_nocursor.png')                 # blink "off" frame
    ImageDraw.Draw(frame).rectangle((part_w + 6, 9, part_w + 18, full.height - 7), fill=CYAN + (255,))
    frame.save(ply / f'type{k}.png')

lines = [
    ('[  OK  ]', GREEN, ' Mounting /home/ruxchipher'),
    ('[  OK  ]', GREEN, ' Starting kvm-lab.target'),
    ('[  OK  ]', GREEN, ' Reached harbourline-freight.domain'),
    ('[  OK  ]', GREEN, ' Arming ruxchipher-sentinel.service'),
    ('[ INFO ]', CYAN, ' loading desktop…'),
]
for i, (tag, tc, rest) in enumerate(lines):
    a = text_img(tag, 'Regular', 15, color=tc)
    b = text_img(rest, 'Regular', 15, color=SUB)
    im = Image.new('RGBA', (a.width + b.width - 8, max(a.height, b.height)), (0, 0, 0, 0))
    im.paste(a, (0, 0), a)
    im.paste(b, (a.width - 8, 0), b)
    im.save(ply / f'line{i}.png')

text_img('ACCESS GRANTED', 'ExtraBold', 20, grad_colors=(CYAN, PURPLE), spacing=8).save(ply / 'granted.png')
text_img('see you soon, Siddique.', 'Bold', 34, grad_colors=(CYAN, PURPLE)).save(ply / 'bye.png')
text_img('powering down the workstation…', 'Light', 17, color=MUTED).save(ply / 'bye_sub.png')

Image.new('RGBA', (420, 4), BLUE[:3] + (40,)).save(ply / 'bar_track.png')
fill = fast_gradient(420, 4, CYAN, PURPLE).convert('RGBA')
fill.save(ply / 'bar_fill.png')
Image.new('RGBA', (13, 26), CYAN + (255,)).save(ply / 'cursor.png')
text_img('●', 'Regular', 22, color=CYAN).save(ply / 'bullet.png')
print('assets ->', OUT)
