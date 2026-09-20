#!/usr/bin/env python3
"""
Generates the PWA manifest screenshots and the Play Store phone screenshots.

There is no browser in this build environment, so these are drawn directly
with Pillow from the app's own design tokens (theme-pro.css / styles.css) and
the real dashboard markup in app.js — same palette, same tile labels, same
information architecture. Re-run with:

    /tmp/venv/bin/python tools/screenshots/render.py

If you later capture real device screenshots, drop them in at the same paths
and sizes and delete this script; nothing else depends on it.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT_DIR = "/usr/share/fonts/truetype/dejavu"

# ---- palette lifted from theme-pro.css / styles.css ------------------------
BG         = (0, 0, 0)
SURFACE    = (11, 23, 40)      # --surface
SURFACE2   = (16, 34, 58)      # --surface-2
CARD_GRAD  = ((16, 33, 58), (9, 21, 34))
LINE       = (41, 72, 110)     # --line
TEXT       = (241, 247, 255)   # --text
MUTED      = (159, 179, 204)   # --muted
PRIMARY    = (96, 165, 250)    # --primary
PRIMARY_D  = (29, 78, 216)     # --primary-strong
ACCENT     = (59, 130, 246)
SUCCESS    = (52, 211, 153)
WARN       = (251, 191, 36)
DANGER     = (251, 113, 133)
CYAN       = (103, 232, 249)


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def rounded(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def vgrad(img, box, top, bottom, radius=0):
    """Vertical gradient clipped to a rounded rect."""
    x0, y0, x1, y1 = box
    w, h = int(x1 - x0), int(y1 - y0)
    if w <= 0 or h <= 0:
        return
    grad = Image.new("RGB", (1, h))
    gp = grad.load()
    for y in range(h):
        t = y / max(1, h - 1)
        gp[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    grad = grad.resize((w, h))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    img.paste(grad, (int(x0), int(y0)), mask)


def hgrad_text(draw, xy, text, f, left, right):
    """Approximates the h1 gradient text by interpolating per character."""
    x, y = xy
    total = draw.textlength(text, font=f) or 1
    for ch in text:
        t = (x - xy[0]) / total
        col = tuple(int(left[i] + (right[i] - left[i]) * min(1, max(0, t))) for i in range(3))
        draw.text((x, y), ch, font=f, fill=col)
        x += draw.textlength(ch, font=f)



# ---------------------------------------------------------------------------
# Vector icons.
#
# DejaVu (the only font in this environment) has no emoji coverage, and the
# app's emoji would render as tofu boxes. These are drawn as real vector
# shapes, which also looks sharper in a store listing than emoji would.
# ---------------------------------------------------------------------------
def icon(d, cx, cy, s, kind, col):
    """Draw icon `kind` centred on (cx, cy) at scale s (icon box = 2s)."""
    lw = max(2, int(s * 0.13))

    if kind == "chart":                       # Analytics & KPIs
        d.line([cx - s, cy + s * .8, cx + s, cy + s * .8], fill=col, width=lw)
        d.line([cx - s, cy + s * .8, cx - s, cy - s], fill=col, width=lw)
        pts = [(cx - s * .6, cy + s * .2), (cx - s * .1, cy - s * .35),
               (cx + s * .35, cy - s * .05), (cx + s * .85, cy - s * .7)]
        d.line(pts, fill=col, width=lw, joint="curve")
        for px, py in pts:
            d.ellipse([px - lw, py - lw, px + lw, py + lw], fill=col)

    elif kind == "camera":                    # Scanner
        d.rounded_rectangle([cx - s, cy - s * .55, cx + s, cy + s * .8], radius=s * .22,
                            outline=col, width=lw)
        d.polygon([(cx - s * .45, cy - s * .55), (cx - s * .3, cy - s * .9),
                   (cx + s * .3, cy - s * .9), (cx + s * .45, cy - s * .55)], outline=col, fill=None)
        d.line([(cx - s * .45, cy - s * .55), (cx - s * .3, cy - s * .9)], fill=col, width=lw)
        d.line([(cx - s * .3, cy - s * .9), (cx + s * .3, cy - s * .9)], fill=col, width=lw)
        d.line([(cx + s * .3, cy - s * .9), (cx + s * .45, cy - s * .55)], fill=col, width=lw)
        d.ellipse([cx - s * .38, cy - s * .2, cx + s * .38, cy + s * .56], outline=col, width=lw)

    elif kind == "clipboard":                 # Daily Logs
        d.rounded_rectangle([cx - s * .75, cy - s * .85, cx + s * .75, cy + s * .9],
                            radius=s * .18, outline=col, width=lw)
        d.rounded_rectangle([cx - s * .32, cy - s * 1.05, cx + s * .32, cy - s * .65],
                            radius=s * .12, outline=col, width=lw)
        for i in range(3):
            y = cy - s * .3 + i * s * .38
            d.line([cx - s * .42, y, cx + s * .42, y], fill=col, width=max(1, lw - 1))

    elif kind == "wave":                      # Condition Monitoring
        import math
        pts = []
        for i in range(49):
            t = i / 48
            x = cx - s + 2 * s * t
            y = cy - math.sin(t * math.pi * 3) * s * .62 * (0.35 + t * .65)
            pts.append((x, y))
        d.line(pts, fill=col, width=lw, joint="curve")

    elif kind == "brain":                     # Problem Solver
        d.ellipse([cx - s * .9, cy - s * .8, cx + s * .9, cy + s * .8], outline=col, width=lw)
        d.line([cx, cy - s * .8, cx, cy + s * .8], fill=col, width=max(1, lw - 1))
        d.arc([cx - s * .6, cy - s * .8, cx + s * .0, cy + s * .0], 90, 270, fill=col, width=max(1, lw - 1))
        d.arc([cx - s * .0, cy + s * .0, cx + s * .6, cy + s * .8], 270, 90, fill=col, width=max(1, lw - 1))

    elif kind == "bars":                      # Reports
        for i, hgt in enumerate([.45, .85, .6, 1.0]):
            x = cx - s * .85 + i * s * .52
            d.rounded_rectangle([x, cy + s * .8 - s * hgt * 1.4, x + s * .3, cy + s * .8],
                                radius=s * .07, fill=col)

    elif kind == "factory":                   # Assets
        d.polygon([(cx - s, cy + s * .85), (cx - s, cy + s * .05), (cx - s * .3, cy + s * .05),
                   (cx - s * .3, cy - s * .35), (cx + s * .25, cy + s * .05),
                   (cx + s * .25, cy - s * .35), (cx + s, cy + s * .05),
                   (cx + s, cy + s * .85)], outline=col, width=lw)
        d.rectangle([cx + s * .45, cy - s * .95, cx + s * .8, cy - s * .2], outline=col, width=lw)
        for i in range(2):
            x = cx - s * .72 + i * s * .55
            d.rectangle([x, cy + s * .38, x + s * .22, cy + s * .62], fill=col)

    elif kind == "toolbox":                   # Work Orders
        d.rounded_rectangle([cx - s, cy - s * .2, cx + s, cy + s * .85], radius=s * .16,
                            outline=col, width=lw)
        d.line([cx - s, cy + s * .3, cx + s, cy + s * .3], fill=col, width=max(1, lw - 1))
        d.arc([cx - s * .5, cy - s * .8, cx + s * .5, cy + s * .1], 180, 360, fill=col, width=lw)

    elif kind == "check":                     # Checklists
        d.rounded_rectangle([cx - s * .85, cy - s * .85, cx + s * .85, cy + s * .85],
                            radius=s * .2, outline=col, width=lw)
        d.line([(cx - s * .42, cy + s * .02), (cx - s * .12, cy + s * .38),
                (cx + s * .48, cy - s * .42)], fill=col, width=lw + 1, joint="curve")

    elif kind == "wrench":                    # Maintenance
        import math
        d.line([(cx - s * .6, cy + s * .7), (cx + s * .45, cy - s * .35)], fill=col, width=lw + 1)
        d.ellipse([cx + s * .18, cy - s * .95, cx + s * .95, cy - s * .18], outline=col, width=lw)
        d.rectangle([cx + s * .3, cy - s * 1.0, cx + s * .68, cy - s * .62], fill=(11, 23, 40))

    elif kind == "box":                       # Spares & Tools
        d.polygon([(cx, cy - s * .9), (cx + s, cy - s * .35), (cx, cy + s * .2),
                   (cx - s, cy - s * .35)], outline=col, width=lw)
        d.line([(cx - s, cy - s * .35), (cx - s, cy + s * .5)], fill=col, width=lw)
        d.line([(cx + s, cy - s * .35), (cx + s, cy + s * .5)], fill=col, width=lw)
        d.line([(cx - s, cy + s * .5), (cx, cy + s * 1.0)], fill=col, width=lw)
        d.line([(cx + s, cy + s * .5), (cx, cy + s * 1.0)], fill=col, width=lw)
        d.line([(cx, cy + s * .2), (cx, cy + s * 1.0)], fill=col, width=lw)

    elif kind == "receipt":                   # Purchase Orders
        d.polygon([(cx - s * .7, cy - s * .9), (cx + s * .7, cy - s * .9), (cx + s * .7, cy + s * .9),
                   (cx + s * .35, cy + s * .65), (cx, cy + s * .9), (cx - s * .35, cy + s * .65),
                   (cx - s * .7, cy + s * .9)], outline=col, width=lw)
        for i in range(2):
            y = cy - s * .35 + i * s * .42
            d.line([cx - s * .4, y, cx + s * .4, y], fill=col, width=max(1, lw - 1))

    elif kind == "book":                      # Manuals
        d.rounded_rectangle([cx - s * .85, cy - s * .8, cx + s * .85, cy + s * .8],
                            radius=s * .12, outline=col, width=lw)
        d.line([cx, cy - s * .8, cx, cy + s * .8], fill=col, width=max(1, lw - 1))

    elif kind == "people":                    # People
        d.ellipse([cx - s * .75, cy - s * .85, cx - s * .05, cy - s * .15], outline=col, width=lw)
        d.arc([cx - s * .95, cy - s * .2, cx + s * .15, cy + s * .95], 180, 360, fill=col, width=lw)
        d.ellipse([cx + s * .1, cy - s * .7, cx + s * .68, cy - s * .12], outline=col, width=max(1, lw - 1))
        d.arc([cx - s * .05, cy - s * .15, cx + s * .9, cy + s * .8], 200, 340, fill=col, width=max(1, lw - 1))

    elif kind == "bell":                      # Notifications
        d.arc([cx - s * .7, cy - s * .9, cx + s * .7, cy + s * .5], 180, 360, fill=col, width=lw)
        d.line([cx - s * .7, cy + s * .35, cx + s * .7, cy + s * .35], fill=col, width=lw)
        d.line([cx - s * .7, cy - s * .2, cx - s * .7, cy + s * .35], fill=col, width=lw)
        d.line([cx + s * .7, cy - s * .2, cx + s * .7, cy + s * .35], fill=col, width=lw)
        d.arc([cx - s * .25, cy + s * .3, cx + s * .25, cy + s * .8], 0, 180, fill=col, width=lw)

    elif kind == "home":
        d.polygon([(cx, cy - s * .9), (cx + s * .95, cy), (cx + s * .65, cy),
                   (cx + s * .65, cy + s * .85), (cx - s * .65, cy + s * .85),
                   (cx - s * .65, cy), (cx - s * .95, cy)], outline=col, width=lw)

    elif kind == "menu":
        for i in range(3):
            y = cy - s * .5 + i * s * .5
            d.line([cx - s * .75, y, cx + s * .75, y], fill=col, width=lw)

    elif kind == "warn":
        d.polygon([(cx, cy - s * .9), (cx + s, cy + s * .75), (cx - s, cy + s * .75)],
                  outline=col, width=lw)
        d.line([cx, cy - s * .35, cx, cy + s * .25], fill=col, width=lw)
        d.ellipse([cx - lw * .6, cy + s * .45, cx + lw * .6, cy + s * .45 + lw * 1.2], fill=col)


def header(img, draw, w, compact=False):
    """The app header: brand block, plant label, sync pill."""
    h = 58 if compact else 64
    draw.rectangle([0, 0, w, h], fill=(7, 16, 28))
    draw.line([0, h, w, h], fill=LINE, width=1)

    pad = 14 if not compact else 10
    vgrad(img, (pad, (h - 40) // 2, pad + 40, (h - 40) // 2 + 40), (37, 99, 235), (79, 70, 229), radius=10)
    d = ImageDraw.Draw(img)
    d.text((pad + 11, (h - 40) // 2 + 9), "PM", font=font(15, True), fill=(255, 255, 255))

    tx = pad + 52
    d.text((tx, h // 2 - 16), "PlantMaster Pro", font=font(15, True), fill=TEXT)
    d.text((tx, h // 2 + 3), "Alpha Cement  •  Line 1", font=font(11), fill=MUTED)

    pill = "Synced"
    pw = d.textlength(pill, font=font(11, True)) + 34
    px0 = w - pad - pw
    rounded(d, (px0, h // 2 - 12, w - pad, h // 2 + 12), 12,
            fill=(5, 46, 39), outline=(4, 120, 87))
    d.ellipse([px0 + 11, h // 2 - 3, px0 + 17, h // 2 + 3], fill=(52, 211, 153))
    d.text((px0 + 24, h // 2 - 7), pill, font=font(11, True), fill=(167, 243, 208))
    return h


def kpi_tile(img, draw, box, label, kind, label_size=11, icon_scale=17):
    vgrad(img, box, (16, 33, 58), (9, 21, 34), radius=16)
    d = ImageDraw.Draw(img)
    rounded(d, box, 16, outline=(45, 85, 133), width=1)
    x0, y0, x1, y1 = box
    d.text((x0 + 14, y0 + 12), label, font=font(label_size, True), fill=MUTED)
    icon(d, (x0 + x1) / 2, (y0 + y1) / 2 + 4, icon_scale, kind, PRIMARY)
    d.text((x0 + 14, y1 - 24), "Open module \u2192", font=font(10), fill=(141, 166, 196))


def module_card(img, draw, box, kind, title, desc, cta, title_size=14, desc_size=11):
    vgrad(img, box, (16, 33, 58), (9, 21, 34), radius=16)
    d = ImageDraw.Draw(img)
    rounded(d, box, 16, outline=(45, 85, 133), width=1)
    x0, y0, x1, y1 = box
    icon(d, x0 + 30, y0 + 26, 12, kind, PRIMARY)
    d.text((x0 + 52, y0 + 15), title, font=font(title_size, True), fill=TEXT)
    d.text((x0 + 16, y0 + 42), desc, font=font(desc_size), fill=MUTED)
    d.text((x0 + 16, y1 - 24), cta, font=font(desc_size, True), fill=CYAN)


def alert_bar(img, draw, box, text, size=12):
    d = ImageDraw.Draw(img)
    rounded(d, box, 12, fill=(58, 38, 8), outline=(146, 92, 12))
    x0, y0, _, y1 = box
    cy = (y0 + y1) / 2
    icon(d, x0 + 24, cy, 10, "warn", (251, 191, 36))
    d.text((x0 + 44, cy - size * .7), text, font=font(size, True), fill=(253, 230, 138))


# ===========================================================================
# Wide (desktop) 1280x720 — manifest form_factor "wide"
# ===========================================================================
def render_wide(path):
    W, H = 1280, 720
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # subtle grid pattern, matching body[data-pattern="grid"]
    for x in range(0, W, 28):
        d.line([x, 0, x, H], fill=(8, 8, 8))
    for y in range(0, H, 28):
        d.line([0, y, W, y], fill=(8, 8, 8))

    top = header(img, d, W)
    d = ImageDraw.Draw(img)

    # ---- left drawer -------------------------------------------------------
    DW = 212
    d.rectangle([0, top, DW, H], fill=(6, 14, 24))
    d.line([DW, top, DW, H], fill=LINE)
    items = [("home", "Dashboard", True), ("factory", "Assets", False), ("toolbox", "Work Orders", False),
             ("check", "Checklists", False), ("wrench", "Maintenance", False), ("box", "Spares & Tools", False),
             ("receipt", "Purchase Orders", False), ("book", "Manuals", False), ("people", "People", False),
             ("chart", "Analytics", False), ("bell", "Notifications", False)]
    y = top + 14
    for kind, label, active in items:
        if active:
            rounded(d, (8, y, DW - 10, y + 34), 9, fill=(22, 54, 95), outline=(47, 112, 186))
        col = PRIMARY if active else MUTED
        icon(d, 26, y + 17, 9, kind, col)
        d.text((46, y + 9), label, font=font(12, True if active else False),
               fill=(191, 232, 255) if active else MUTED)
        y += 38

    # ---- main --------------------------------------------------------------
    M = DW + 26
    hgrad_text(d, (M, top + 20), "Dashboard", font(30, True), (255, 255, 255), ACCENT)
    d.text((M, top + 60), "Alpha Cement  •  Line 1  •  owner", font=font(12), fill=MUTED)

    btn_w = 128
    rounded(d, (W - 26 - btn_w, top + 22, W - 26, top + 56), 10,
            fill=(13, 27, 45), outline=(56, 87, 127))
    icon(d, W - 26 - btn_w + 24, top + 39, 9, "bell", WARN)
    d.text((W - 26 - btn_w + 42, top + 31), "3 Alerts", font=font(12, True), fill=TEXT)

    alert_bar(img, d, (M, top + 84, W - 26, top + 122),
              "Checklist failure on Kiln ID Fan \u2014 alarm raised 12 minutes ago")
    d = ImageDraw.Draw(img)

    # KPI tiles (6, as in app.js)
    tiles = [("Analytics", "chart"), ("Scanner", "camera"), ("Daily Logs", "clipboard"),
             ("Condition", "wave"), ("Problem Solver", "brain"), ("Reports", "bars")]
    gx, gy = M, top + 138
    tw, th, gap = (W - 26 - M - 5 * 12) / 6, 96, 12
    for i, (label, kind) in enumerate(tiles):
        x = gx + i * (tw + gap)
        kpi_tile(img, d, (x, gy, x + tw, gy + th), label, kind)
    d = ImageDraw.Draw(img)

    # module cards
    cards = [("factory", "Assets", "Equipment register, state and QR records", "Open Assets \u2192"),
             ("toolbox", "Work Orders", "Assigned corrective work and completion", "Open Work Orders \u2192"),
             ("box", "Spares & Tools", "Stock, custody and calibration", "Open Inventory \u2192")]
    cy = gy + th + 14
    cw = (W - 26 - M - 2 * 14) / 3
    ch = 88
    for i, (kind, t, dsc, cta) in enumerate(cards):
        cx = M + i * (cw + 14)
        module_card(img, d, (cx, cy, cx + cw, cy + ch), kind, t, dsc, cta)

    # ---- stat strip --------------------------------------------------------
    sy = cy + ch + 12
    stats = [("OPEN WORK ORDERS", "18", PRIMARY), ("CLOSED TODAY", "7", SUCCESS),
             ("OVERDUE", "3", DANGER), ("ASSETS MONITORED", "246", TEXT),
             ("CHECKLISTS DUE", "5", WARN)]
    sw = (W - 26 - M - 4 * 12) / 5
    for i, (label, value, col) in enumerate(stats):
        x = M + i * (sw + 12)
        vgrad(img, (x, sy, x + sw, sy + 64), (16, 33, 58), (9, 21, 34), radius=14)
        dd = ImageDraw.Draw(img)
        rounded(dd, (x, sy, x + sw, sy + 64), 14, outline=(45, 85, 133), width=1)
        dd.text((x + 14, sy + 11), label, font=font(9, True), fill=MUTED)
        dd.text((x + 14, sy + 25), value, font=font(27, True), fill=col)
    d = ImageDraw.Draw(img)

    # ---- recent work orders table -----------------------------------------
    ty = sy + 76
    th2 = H - ty - 16
    vgrad(img, (M, ty, W - 26, ty + th2), (14, 29, 50), (8, 18, 31), radius=14)
    d = ImageDraw.Draw(img)
    rounded(d, (M, ty, W - 26, ty + th2), 14, outline=(45, 85, 133), width=1)
    d.text((M + 18, ty + 14), "Recent work orders", font=font(13, True), fill=TEXT)

    cols = [M + 18, M + 140, M + 300, M + 640, M + 800, M + 920]
    hy = ty + 40
    for label, x in zip(["WO NUMBER", "ASSET", "TASK", "ASSIGNED", "PRIORITY", "STATUS"], cols):
        d.text((x, hy), label, font=font(9, True), fill=(184, 215, 245))
    d.line([M + 14, hy + 18, W - 40, hy + 18], fill=(32, 58, 92))

    rows = [("WO-2026-0418", "Kiln ID Fan", "Bearing temperature high \u2014 inspect DE bearing",
             "A. Rahman", "Critical", DANGER, "In progress", WARN),
            ("WO-2026-0417", "Raw Mill 2", "Replace worn discharge liner segment",
             "S. Iqbal", "High", WARN, "Open", PRIMARY),
            ("WO-2026-0416", "Packing Line 1", "Weekly lubrication route",
             "M. Tariq", "Medium", MUTED, "Completed", SUCCESS),
            ("WO-2026-0415", "Cooler Grate Drive", "Hydraulic pressure drop investigation",
             "A. Rahman", "High", WARN, "Completed", SUCCESS)]
    ry = hy + 28
    for wo, asset, task, who, pri, pcol, st, scol in rows:
        if ry + 24 > ty + th2 - 6:
            break
        d.text((cols[0], ry), wo, font=font(11, True), fill=TEXT)
        d.text((cols[1], ry), asset, font=font(11), fill=TEXT)
        d.text((cols[2], ry), task, font=font(11), fill=MUTED)
        d.text((cols[3], ry), who, font=font(11), fill=MUTED)
        d.text((cols[4], ry), pri, font=font(11, True), fill=pcol)
        bw = d.textlength(st, font=font(10, True)) + 18
        rounded(d, (cols[5], ry - 3, cols[5] + bw, ry + 18), 9,
                fill=(9, 21, 34), outline=scol)
        d.text((cols[5] + 9, ry + 1), st, font=font(10, True), fill=scol)
        ry += 30

    img.save(path, "PNG", optimize=True)
    return img.size


# ===========================================================================
# Narrow (phone) 720x1280 — manifest form_factor "narrow" + Play listing
# ===========================================================================
def render_narrow(path):
    W, H = 720, 1280
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    for x in range(0, W, 28):
        d.line([x, 0, x, H], fill=(8, 8, 8))
    for y in range(0, H, 28):
        d.line([0, y, W, y], fill=(8, 8, 8))

    top = header(img, d, W)
    d = ImageDraw.Draw(img)

    M = 20
    hgrad_text(d, (M, top + 22), "Dashboard", font(34, True), (255, 255, 255), ACCENT)
    d.text((M, top + 68), "Alpha Cement  •  Line 1  •  owner", font=font(14), fill=MUTED)

    alert_bar(img, d, (M, top + 100, W - M, top + 148),
              "Checklist failure \u2014 Kiln ID Fan", size=14)
    d = ImageDraw.Draw(img)

    tiles = [("Analytics & KPIs", "chart"), ("Scanner", "camera"), ("Daily Logs", "clipboard"),
             ("Condition Monitoring", "wave"), ("Problem Solver", "brain"), ("Reports", "bars")]
    gy = top + 166
    tw = (W - 2 * M - 14) / 2
    th = 128
    for i, (label, kind) in enumerate(tiles):
        x = M + (i % 2) * (tw + 14)
        y = gy + (i // 2) * (th + 14)
        kpi_tile(img, d, (x, y, x + tw, y + th), label, kind, label_size=13, icon_scale=21)
    d = ImageDraw.Draw(img)

    cy = gy + 3 * (th + 14) + 6
    # Stat strip: the numbers a supervisor checks before anything else.
    stats = [("OPEN", "18", PRIMARY), ("OVERDUE", "3", DANGER), ("DUE TODAY", "5", WARN)]
    stw = (W - 2 * M - 2 * 12) / 3
    for i, (label, value, col) in enumerate(stats):
        x = M + i * (stw + 12)
        vgrad(img, (x, cy, x + stw, cy + 78), (16, 33, 58), (9, 21, 34), radius=14)
        dd = ImageDraw.Draw(img)
        rounded(dd, (x, cy, x + stw, cy + 78), 14, outline=(45, 85, 133), width=1)
        dd.text((x + 14, cy + 12), label, font=font(10, True), fill=MUTED)
        dd.text((x + 14, cy + 30), value, font=font(32, True), fill=col)
    d = ImageDraw.Draw(img)

    cards = [("factory", "Assets", "Equipment register, state and QR records", "Open Assets \u2192"),
             ("toolbox", "Work Orders", "Assigned corrective work and completion", "Open Work Orders \u2192"),
             ("check", "Checklists", "Templates and completed runs", "Open Checklists \u2192"),
             ("box", "Spares & Tools", "Stock, custody and calibration", "Open Inventory \u2192")]
    ch = 96
    cstart = cy + 78 + 14
    for i, (kind, t, dsc, cta) in enumerate(cards):
        y = cstart + i * (ch + 12)
        if y + ch > H - 84:
            break
        module_card(img, d, (M, y, W - M, y + ch), kind, t, dsc, cta, title_size=16, desc_size=12)

    # bottom navigation (mobile-bottom, 5 columns)
    bh = 76
    d.rectangle([0, H - bh, W, H], fill=(7, 16, 28))
    d.line([0, H - bh, W, H - bh], fill=LINE)
    nav = [("home", "Home", True), ("factory", "Assets", False), ("toolbox", "Work", False),
           ("camera", "Scan", False), ("menu", "More", False)]
    cwid = W / 5
    for i, (kind, label, active) in enumerate(nav):
        cx = cwid * i + cwid / 2
        col = PRIMARY if active else MUTED
        icon(d, cx, H - bh + 26, 12, kind, col)
        lw = d.textlength(label, font=font(11, True))
        d.text((cx - lw / 2, H - bh + 48), label, font=font(11, True), fill=col)

    img.save(path, "PNG", optimize=True)
    return img.size


if __name__ == "__main__":
    out = os.path.join(ROOT, "screenshots")
    os.makedirs(out, exist_ok=True)
    print("wide  ", render_wide(os.path.join(out, "dashboard-wide.png")))
    print("narrow", render_narrow(os.path.join(out, "dashboard-narrow.png")))
