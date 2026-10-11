#!/usr/bin/env python3
"""Generate the three blueprint sheets in docs/blueprints/.

The SVG files are output of this script. To change a sheet, edit this file,
not the SVG, then regenerate:

    python3 docs/tools/blueprints/blueprints.py

The script writes 01-system.svg, 02-setup-sequence.svg and 03-add-vault.svg
into docs/blueprints/. It uses the Python standard library only, and the same
input always gives the same bytes, so `git diff` shows only real changes.

The frame (grid, border, title block, legend) is in the class Sheet and is the
same on every sheet. Each sheet is one function: sheet1, sheet2, sheet3.

To look at the result, render PNGs with `render.sh` in this folder (optional;
it needs Google Chrome). Do not commit the PNGs.
"""
import os
from html import escape

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "docs", "blueprints")

BG = "#0b3d6e"
CYAN = "#7fdbff"
INK = "#ffffff"
SOFT = "#c4e2fb"
FONT = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"

STYLE = f"""
    text {{ font-family: {FONT}; fill: {INK}; }}
    .bg {{ fill: {BG}; }}
    .frame {{ fill: none; stroke: {INK}; stroke-width: 3; }}
    .margin {{ fill: none; stroke: {INK}; stroke-width: 1.2; }}
    .tick {{ stroke: {INK}; stroke-width: 1.2; }}
    .lab {{ font-size: 16px; font-weight: 700; letter-spacing: .05em; }}
    .big {{ font-size: 18px; font-weight: 700; letter-spacing: .05em; }}
    .ann {{ font-size: 14px; fill: {SOFT}; }}
    .code {{ font-size: 14px; fill: {CYAN}; }}
    .zone {{ font-size: 15px; font-weight: 700; letter-spacing: .16em; fill: {CYAN}; }}
    .num {{ font-size: 16px; font-weight: 700; fill: {BG}; }}
    .tbk {{ font-size: 14px; fill: {SOFT}; letter-spacing: .08em; }}
    .halo {{ paint-order: stroke; stroke: {BG}; stroke-width: 5px; stroke-linejoin: round; }}
    .solid {{ fill: {BG}; stroke: {INK}; stroke-width: 2; }}
    .hatch {{ fill: url(#hatch); stroke: {INK}; stroke-width: 2; }}
    .opt {{ stroke-dasharray: 8 5; }}
    .hinge {{ fill: {BG}; stroke: {CYAN}; stroke-width: 3; }}
    .zbox {{ fill: none; stroke: {CYAN}; stroke-width: 1.4; stroke-dasharray: 10 6; }}
    .zin {{ fill: none; stroke: {SOFT}; stroke-width: 1.2; stroke-dasharray: 3 5; }}
    .w {{ fill: none; stroke: {INK}; stroke-width: 2; }}
    .c {{ fill: none; stroke: {CYAN}; stroke-width: 2; }}
    .d {{ stroke-dasharray: 7 5; }}
    .life {{ fill: none; stroke: {SOFT}; stroke-width: 1.5; stroke-dasharray: 2 6; }}
    .dot {{ fill: {CYAN}; }}
    .callout {{ fill: {BG}; stroke: {CYAN}; stroke-width: 2; }}
"""


def esc(s):
    return escape(s, quote=True)


class Sheet:
    def __init__(self, w, h, n, title, a11y_title, desc):
        self.w, self.h, self.n, self.title = w, h, n, title
        self.a11y_title, self.desc = a11y_title, desc
        self.body = []

    def add(self, s):
        self.body.append(s)

    # ---- primitives -----------------------------------------------------
    def text(self, x, y, s, cls="ann", anchor="middle", halo=False):
        c = cls + (" halo" if halo else "")
        a = "" if anchor == "start" else f' text-anchor="{anchor}"'
        self.add(f'<text class="{c}" x="{x}" y="{y}"{a}>{esc(s)}</text>')

    def box(self, x, y, w, h, title, lines=(), kind="solid", opt=False,
            title_cls="lab", anchor="middle", pad=14, top=28, step=20):
        cls = kind + (" opt" if opt else "")
        if kind == "hatch":
            # Solid base under the hatch so the grid does not show through.
            self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{BG}"/>')
        self.add(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}"/>')
        tx = x + w / 2 if anchor == "middle" else x + pad
        halo = kind == "hatch"
        if title:
            self.text(tx, y + top, title, title_cls, anchor, halo)
        ly = y + top + (24 if title else 0)
        for item in lines:
            s, c = item if isinstance(item, tuple) else (item, "ann")
            self.text(tx, ly, s, c, anchor, halo)
            ly += step

    def zone(self, x, y, w, h, label, inner=False, lx=None, ly=None):
        self.add(f'<rect class="{"zin" if inner else "zbox"}" x="{x}" y="{y}" width="{w}" height="{h}"/>')
        if label:
            self.text(lx if lx is not None else x + 14, ly if ly is not None else y + 24,
                      label, "zone", "start", True)

    def wire(self, pts, cls="w", end=True, start=False, dash=False):
        d = "M" + " L".join(f"{px} {py}" for px, py in pts)
        mk = "c" if cls == "c" else "w"
        m = ""
        if end:
            m += f' marker-end="url(#a{mk})"'
        if start:
            m += f' marker-start="url(#a{mk})"'
        self.add(f'<path class="{cls}{" d" if dash else ""}" d="{d}"{m}/>')

    def badge(self, cx, cy, n):
        self.add(f'<circle cx="{cx}" cy="{cy}" r="15" fill="{CYAN}"/>')
        self.text(cx, cy + 6, str(n), "num")

    # ---- the common frame ------------------------------------------------
    def frame_defs(self):
        return f"""  <defs>
    <style>{STYLE}    </style>
    <pattern id="fine" width="20" height="20" patternUnits="userSpaceOnUse">
      <path d="M20 0H0V20" fill="none" stroke="#ffffff" stroke-opacity=".07" stroke-width="1"/>
    </pattern>
    <pattern id="coarse" width="100" height="100" patternUnits="userSpaceOnUse">
      <rect width="100" height="100" fill="url(#fine)"/>
      <path d="M100 0H0V100" fill="none" stroke="#ffffff" stroke-opacity=".16" stroke-width="1"/>
    </pattern>
    <pattern id="hatch" width="12" height="12" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="12" height="12" fill="{BG}"/>
      <line x1="0" y1="0" x2="0" y2="12" stroke="#ffffff" stroke-opacity=".32" stroke-width="2"/>
    </pattern>
    <marker id="aw" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" markerUnits="userSpaceOnUse" orient="auto-start-reverse">
      <path d="M0 0L10 5L0 10z" fill="{INK}"/>
    </marker>
    <marker id="ac" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" markerUnits="userSpaceOnUse" orient="auto-start-reverse">
      <path d="M0 0L10 5L0 10z" fill="{CYAN}"/>
    </marker>
  </defs>
"""

    def frame_sheet(self):
        w, h = self.w, self.h
        out = [
            f'  <rect class="bg" width="{w}" height="{h}"/>',
            f'  <rect x="32" y="32" width="{w-64}" height="{h-64}" fill="url(#coarse)"/>',
            f'  <rect class="frame" x="16" y="16" width="{w-32}" height="{h-32}"/>',
            f'  <rect class="margin" x="32" y="32" width="{w-64}" height="{h-64}"/>',
        ]
        # Reference ticks in the margin, every 200 units.
        for x in range(200, w - 100, 200):
            out.append(f'  <path class="tick" d="M{x} 16V32M{x} {h-32}V{h-16}"/>')
        for y in range(200, h - 100, 200):
            out.append(f'  <path class="tick" d="M16 {y}H32M{w-32} {y}H{w-16}"/>')
        return "\n".join(out) + "\n"

    def title_block(self):
        tw, th = 520, 196
        x0, y0 = self.w - 32 - tw, self.h - 32 - th
        r1, r2, r3 = y0 + 40, y0 + 86, y0 + 124
        s = []
        a = s.append
        a(f'<g id="title-block">')
        a(f'<rect x="{x0}" y="{y0}" width="{tw}" height="{th}" fill="{BG}" stroke="{INK}" stroke-width="2"/>')
        a(f'<path class="margin" d="M{x0} {r1}H{x0+tw}M{x0} {r2}H{x0+tw}M{x0} {r3}H{x0+tw}'
          f'M{x0+220} {r2}V{r3}M{x0+340} {r2}V{r3}"/>')
        a(f'<text class="tbk" x="{x0+12}" y="{y0+26}">PROJECT</text>')
        a(f'<text class="big" x="{x0+120}" y="{y0+27}">OBSIDIAN-LIVESYNC-MCP</text>')
        a(f'<text class="tbk" x="{x0+12}" y="{r1+29}">TITLE</text>')
        a(f'<text class="big" x="{x0+120}" y="{r1+30}">{esc(self.title)}</text>')
        a(f'<text class="lab" x="{x0+12}" y="{r2+25}">SHEET {self.n} / 3</text>')
        a(f'<text class="lab" x="{x0+232}" y="{r2+25}">REV 1</text>')
        a(f'<text class="lab" x="{x0+352}" y="{r2+25}">2026-10-11</text>')
        # Legend
        ly1, ly2 = r3 + 26, r3 + 56
        a(f'<rect class="solid" x="{x0+12}" y="{ly1-14}" width="34" height="18"/>')
        a(f'<text class="ann" x="{x0+54}" y="{ly1}">AUTOMATIC</text>')
        a(f'<rect x="{x0+148}" y="{ly1-14}" width="34" height="18" class="hatch"/>')
        a(f'<text class="ann" x="{x0+190}" y="{ly1}">YOU</text>')
        a(f'<path class="w" d="M{x0+240} {ly1-5}H{x0+290}" marker-end="url(#aw)"/>')
        a(f'<text class="ann" x="{x0+300}" y="{ly1}">data, next step</text>')
        a(f'<path class="w d" d="M{x0+12} {ly2-5}H{x0+62}" marker-end="url(#aw)"/>')
        a(f'<text class="ann" x="{x0+72}" y="{ly2}">timer job, optional</text>')
        a(f'<path class="c" d="M{x0+262} {ly2-5}H{x0+312}" marker-end="url(#ac)" marker-start="url(#ac)"/>')
        a(f'<text class="ann" x="{x0+322}" y="{ly2}">two-way sync</text>')
        a('</g>')
        return "  " + "\n  ".join(s) + "\n"

    def render(self):
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
                f'width="{self.w}" height="{self.h}" role="img" aria-labelledby="t d">\n'
                f'  <title id="t">{esc(self.a11y_title)}</title>\n'
                f'  <desc id="d">{esc(self.desc)}</desc>\n')
        drawing = "  <g id=\"drawing\">\n    " + "\n    ".join(self.body) + "\n  </g>\n"
        return head + self.frame_defs() + self.frame_sheet() + drawing + self.title_block() + "</svg>\n"


# =========================================================================
# SHEET 1: SYSTEM OVERVIEW
# =========================================================================
def sheet1():
    s = Sheet(1600, 1200, 1, "SYSTEM OVERVIEW",
              "Sheet 1 of 3: system overview of obsidian-livesync-mcp",
              "Devices with Obsidian and Self-hosted LiveSync sync end-to-end encrypted notes over HTTPS "
              "through Caddy to CouchDB, which has one database per vault. The bridge copies notes between "
              "CouchDB and the mirror, /srv/vaults/<vault>, as plain files. The MCP server reads and writes "
              "the mirror for Claude, through the connector at mcp.<domain>/mcp, with Google OAuth and one "
              "allowed email. Systemd timers copy the mirror to the history (git, every 15 minutes, optional "
              "GitHub push), the backup (rclone to Google Drive, nightly) and run the staleness check (hourly). "
              "From the repo, seed-vault.sh copies vault/template into the mirror, and skills/ go to Claude.")

    # Zones
    s.zone(40, 70, 220, 370, "DEVICES")
    s.zone(40, 470, 220, 350, "CLAUDE")
    s.zone(290, 70, 1010, 750, "SERVER", lx=304, ly=94)
    s.zone(305, 112, 545, 676, "", inner=True)
    s.text(320, 776, "docker compose", "ann", "start", True)
    s.zone(1320, 320, 250, 310, "EXTERNAL")
    s.zone(40, 860, 460, 290, "REPO")

    # Devices
    s.box(60, 112, 180, 110, "LAPTOP", ["obsidian +", "self-hosted", "livesync"])
    s.box(60, 262, 180, 110, "PHONE", ["obsidian +", "self-hosted", "livesync"])
    s.text(150, 404, "end-to-end encrypted", "ann")
    s.text(150, 424, "sync over https", "ann")

    # Claude
    s.box(80, 512, 160, 110, "CLAUDE.AI", ["web · phone", "skill zips"])
    s.box(80, 652, 160, 110, "CLAUDE CODE", ["vault plugin", "+ connector"])
    s.text(160, 788, "connector at", "ann")
    s.text(160, 808, "mcp.<domain>/mcp", "code")

    # Caddy
    s.box(325, 140, 150, 620, "CADDY", ["tls", "let's encrypt", "80 · 443"])
    s.text(400, 300, "couch.<domain>", "code")
    s.text(400, 660, "mcp.<domain>", "code")
    s.wire([(240, 167), (325, 167)], "c", start=True)
    s.wire([(240, 317), (325, 317)], "c", start=True)
    s.wire([(240, 567), (325, 567)])
    s.wire([(240, 707), (325, 707)])

    # Containers
    s.box(545, 140, 280, 120, "COUCHDB", ["one database per vault", "encrypted chunks"])
    s.box(545, 340, 280, 110, "LIVESYNC-BRIDGE", ["uid 1993", "decrypts · encrypts"])
    s.box(545, 540, 280, 220, "MCP SERVER",
          ["google oauth", "one allowed email", ("list_notes", "code"), ("write_note", "code"),
           ("vault_now", "code"), ("lint_vault  ...", "code")])
    s.wire([(475, 200), (545, 200)], "c", start=True)
    s.wire([(475, 640), (545, 640)])
    s.wire([(685, 260), (685, 340)], "c", start=True)

    # Mirror: the hinge
    s.add(f'<rect class="hinge" x="875" y="340" width="200" height="420"/>')
    s.text(975, 368, "MIRROR", "lab")
    for i, (t, c) in enumerate([("/srv/vaults/", "code"), ("<vault>", "code"), ("plain files", "ann"),
                                ("owner uid 1993", "ann")]):
        s.text(975, 392 + 20 * i, t, c)
    s.text(975, 720, "every job", "ann")
    s.text(975, 740, "reads it", "ann")
    s.wire([(825, 395), (875, 395)], "c", start=True)
    s.wire([(825, 650), (875, 650)], start=True)
    s.text(850, 636, "r/w", "ann", halo=True)

    # Timers
    s.text(1100, 326, "SYSTEMD TIMERS", "zone", "start", True)
    s.box(1100, 340, 185, 130, "HISTORY", ["git · 15 min", ("/srv/git/", "code"), ("<vault>.git", "code")])
    s.box(1100, 500, 185, 110, "BACKUP", ["rclone", "nightly 03:30"])
    s.box(1100, 640, 185, 120, "STALENESS", ["check", "hourly", "stale > 24 h"])
    for y in (405, 555, 700):
        s.wire([(1075, y), (1100, y)], dash=True)

    # External
    s.box(1340, 350, 210, 110, "GITHUB", ["private repo", "per vault", ], opt=True)
    s.text(1445, 482, "optional", "ann", halo=True)
    s.box(1340, 500, 210, 110, "GOOGLE DRIVE", [("gdrive:", "code"), ("ObsidianBackup", "code")])
    s.wire([(1285, 405), (1340, 405)], dash=True)
    s.wire([(1285, 555), (1340, 555)], dash=True)

    # Google OAuth
    s.box(545, 870, 280, 100, "GOOGLE OAUTH", ["external sign-in", "gives your email"])
    s.wire([(685, 760), (685, 870)], start=True)

    # Repo
    s.box(60, 905, 210, 125, "VAULT/TEMPLATE", [("CLAUDE.md", "code"), ("_templates/", "code"),
                                                 ("_bases/", "code")])
    s.text(165, 1052, "schema", "ann")
    s.box(295, 905, 185, 125, "SKILLS/", ["13 skills", "plugin or zips"])
    # Skills go to the CLAUDE zone as a whole: a bus touches both boxes.
    s.wire([(387, 905), (387, 842), (54, 842), (54, 597), (80, 597)])
    s.wire([(54, 737), (80, 737)])
    s.add(f'<circle class="dot" cx="54" cy="737" r="3.5"/>')
    s.wire([(165, 1062), (165, 1100), (975, 1100), (975, 760)])
    s.text(640, 1090, "seed-vault.sh", "code", halo=True)
    return s


# =========================================================================
# SHEET 2: SETUP ORDER
# =========================================================================
def sheet2():
    s = Sheet(1600, 1100, 2, "SETUP ORDER",
              "Sheet 2 of 3: setup order, in eight numbered steps",
              "Eight steps in four lanes: server, vault, devices and Claude. 1 DNS: two A records, you. "
              "2 Google OAuth client, you. 3 bootstrap.sh on the server: secrets, folders, CouchDB and TLS, "
              "MCP server, timers, script. 4 Drive backup: rclone config, you, optional. 5 First vault: "
              "add-vault.sh <name>, script, and you connect the first device; the schema is seeded. "
              "6 Obsidian device settings: template folder _templates, attachment folder _attachments, you. "
              "7 Claude: the connector in claude.ai and the skills, you. 8 Check: doctor.sh, script, then ask "
              "Claude to set up a topic, you.")

    lanes = ["SERVER", "VAULT", "DEVICES", "CLAUDE"]
    top, lh, left, right = 60, 200, 40, 1560
    for i, name in enumerate(lanes):
        y = top + i * lh
        s.add(f'<rect x="{left}" y="{y}" width="{right-left}" height="{lh}" fill="none" '
              f'stroke="{CYAN}" stroke-width="1.2" stroke-dasharray="10 6"/>')
        s.add(f'<rect x="{left}" y="{y}" width="40" height="{lh}" fill="{BG}" stroke="{CYAN}" stroke-width="1.2"/>')
        s.add(f'<text class="zone" transform="translate({left+26} {y+lh/2}) rotate(-90)" '
              f'text-anchor="middle">{name}</text>')

    def lane_y(i):
        return top + i * lh

    cw = 182          # column width
    x0 = 100          # first column left
    bw, bh = 160, 150

    def col(c):
        return x0 + c * cw

    def step(c, lane, n, title, lines, kind, opt=False, h=bh):
        x, y = col(c), lane_y(lane) + (lh - h) / 2
        s.box(x, y, bw, h, title, lines, kind, opt=opt, top=54)
        s.badge(x + bw / 2, y + 24, n)
        return x, y

    step(0, 0, 1, "DNS", ["two A records", ("couch.<domain>", "code"), ("mcp.<domain>", "code")], "hatch")
    step(1, 0, 2, "GOOGLE OAUTH", ["web client", "id + secret", "into .env"], "hatch")
    step(2, 0, 3, "BOOTSTRAP", [("bootstrap.sh", "code"), "secrets, folders", "couchdb + tls",
                                 "mcp server", "timers"], "solid", h=180)
    step(3, 0, 4, "DRIVE", [("rclone config", "code"), "backup remote", "optional"], "hatch", opt=True)
    step(4, 1, 5, "FIRST VAULT", [("add-vault.sh", "code"), ("<name>", "code"), "schema seeded"], "solid")
    step(4, 2, 5, "FIRST DEVICE", ["import the", "setup uri", "upload notes"], "hatch")
    step(5, 2, 6, "SETTINGS", ["per device:", ("_templates", "code"), ("_attachments", "code")], "hatch")
    step(6, 3, 7, "CLAUDE", ["connector in", "claude.ai", "skills: plugin", "or zips"], "hatch", h=170)
    step(7, 0, 8, "CHECK", [("doctor.sh", "code"), "checks the", "setup"], "solid")
    step(7, 3, 8, "ASK CLAUDE", ["\"set up a", "topic for X\""], "hatch")

    def mid(lane):
        return lane_y(lane) + lh / 2

    # SERVER lane: 1 -> 2 -> 3 -> 4
    for c in range(3):
        s.wire([(col(c) + bw, mid(0)), (col(c + 1), mid(0))])
    # 4 -> 5 (vault lane)
    s.wire([(col(3) + bw, mid(0)), (col(3) + bw + 11, mid(0)), (col(3) + bw + 11, mid(1)), (col(4), mid(1))])
    # 5 vault <-> 5 device
    s.wire([(col(4) + bw / 2, lane_y(1) + (lh + bh) / 2), (col(4) + bw / 2, lane_y(2) + (lh - bh) / 2)],
           "c", start=True)
    # 5 device -> 6
    s.wire([(col(4) + bw, mid(2)), (col(5), mid(2))])
    # 6 -> 7
    s.wire([(col(5) + bw, mid(2)), (col(5) + bw + 11, mid(2)), (col(5) + bw + 11, mid(3)), (col(6), mid(3))])
    # 7 -> 8 check (server) -> 8 ask (claude)
    s.wire([(col(6) + bw, mid(3)), (col(6) + bw + 11, mid(3)), (col(6) + bw + 11, mid(0)), (col(7), mid(0))])
    s.wire([(col(7) + bw / 2, lane_y(0) + (lh + bh) / 2), (col(7) + bw / 2, lane_y(3) + (lh - bh) / 2)])

    # Notes in the free space
    s.text(col(0), lane_y(1) + 40, "1-4: once per server, with no vault", "ann", "start")
    s.text(col(0), lane_y(1) + 62, "5: once per vault", "ann", "start")
    s.text(col(0), lane_y(1) + 84, "6: once per device", "ann", "start")
    s.text(col(0), lane_y(1) + 106, "7: once per claude account", "ann", "start")
    s.text(col(0), lane_y(2) + 40, "other devices: a fresh setup uri", "ann", "start")
    s.text(col(0), lane_y(2) + 62, "from the first device; download only", "ann", "start")
    return s


# =========================================================================
# SHEET 3: ADD A VAULT
# =========================================================================


def sheet3():
    X = {"you": 230, "srv": 760, "dev": 1290}
    BW = 290
    steps = [
        # lane, title, lines, message after: (target, label, wire class) or None
        ("you", "RUN THE SCRIPT", [("sudo ./scripts/", "code"), ("add-vault.sh <name>", "code")],
         ("srv", "<name>", "w")),
        ("srv", "CREATE THE DATABASE", ["the provisioner writes", "livesync's version document"], None),
        ("srv", "PRINT A SETUP URI", ["+ one-time passphrase", "then wait for a device"],
         ("you", "setup uri + passphrase", "w")),
        ("you", "IMPORT THE SETUP URI", ["on the first device"], ("dev", "setup uri + passphrase", "w")),
        ("dev", "WRITE THE SETTINGS", ["livesync settings", "into the database"], None),
        ("dev", "UPLOAD THE NOTES", ["first full upload"],
         ("srv", "notes", "c")),
        ("srv", "SEE THE DEVICE", ["notes, or a rewritten", "version document"], None),
        ("srv", "WAIT FOR QUIET", ["no change for 30 s"], None),
        ("srv", "CONNECT THE VAULT", [("add to VAULTS", "code"), "start the bridge", "the mirror fills"], None),
        ("srv", "FIRST HISTORY COMMIT", [("/srv/git/<name>.git", "code")], None),
        ("srv", "OFFER THE SCHEMA", ["if no root CLAUDE.md"], ("you", "seed it now? [Y/n]", "w")),
        ("you", "ANSWER Y", ["or --no-seed to skip"], ("srv", "Y", "w")),
        ("srv", "COPY THE SCHEMA", [("seed-vault.sh", "code"), "into the mirror", "the bridge sends it"],
         ("dev", "schema files", "c")),
        ("dev", "FILES ARRIVE", [("CLAUDE.md", "code"), ("_templates/  _bases/", "code")], None),
    ]

    head_y = 60
    y = head_y + 70 + 26
    placed = []
    prev_msg = None
    bottom = {k: 0 for k in X}
    for lane, title, lines, m in steps:
        h = 44 + 20 * len(lines)
        if prev_msg is not None and prev_msg[0] == lane:
            y = prev_msg[1] - 20
        y = max(y, bottom[lane] + 22)
        bottom[lane] = y + h
        placed.append((lane, y, h, title, lines, m))
        prev_msg = (m[0], y + h - 20) if m else None
        y = y + h + 10
    end_y = y + 4
    H = end_y + 32 + 196 + 22

    s = Sheet(1600, H, 3, "ADD A VAULT",
              "Sheet 3 of 3: add a vault with add-vault.sh",
              "A sequence with three lifelines: you, the server that runs add-vault.sh, and the device that "
              "runs Obsidian. You run sudo ./scripts/add-vault.sh <name>. The server creates the database, and "
              "the provisioner writes the LiveSync version document. The server prints a Setup URI and a "
              "one-time passphrase, and waits. You import the Setup URI on the first device. The device writes "
              "the LiveSync settings into the database and uploads its notes. The server sees the device: "
              "notes, or a rewritten version document. It waits until the upload is quiet for 30 seconds. It "
              "adds the vault to VAULTS, starts the bridge, and the mirror fills. It makes the first history "
              "commit. If the vault has no root CLAUDE.md, it offers the schema: seed it now? [Y/n]. You "
              "answer Y, or use --no-seed to skip. The server runs seed-vault.sh: the schema goes into the "
              "mirror, and the bridge sends the files to the device. Callout: the first device writes the "
              "LiveSync settings of the vault, and the bridge reads them. If the bridge connects first, the "
              "settings do not match.")

    for k, title, sub, kind in (("you", "YOU", ("at the terminal", "ann"), "hatch"),
                                ("srv", "SERVER", ("add-vault.sh", "code"), "solid"),
                                ("dev", "DEVICE", ("obsidian + livesync", "ann"), "solid")):
        s.add(f'<path class="life" d="M{X[k]} {head_y+70}V{end_y}"/>')
        s.box(X[k] - 130, head_y, 260, 70, title, [sub], kind, top=28)

    for n, (lane, y, h, title, lines, m) in enumerate(placed, 1):
        kind = "hatch" if lane == "you" else "solid"
        s.box(X[lane] - BW / 2, y, BW, h, title, lines, kind, top=27)
        s.badge(X[lane] - BW / 2, y, n)
        if m:
            tgt, label, cls = m
            my = y + h - 20
            a, b = X[lane], X[tgt]
            sgn = 1 if b > a else -1
            s.wire([(a + sgn * BW / 2, my), (b - sgn * BW / 2, my)], cls)
            lx = (a + b) / 2
            if {lane, tgt} == {"you", "dev"}:
                lx = X["srv"] + 265 * sgn
            if label:
                s.text(lx, my - 9, label, "code" if label[0] in "<" or "[Y/n]" in label or label == "Y" else "ann", halo=True)

    # Side notes, off the message rows.
    nx = X["srv"] + BW / 2 + 24
    _, y3, *_ = placed[2]
    s.text(nx, y3 + 26, "ctrl+c is safe here:", "ann", "start")
    s.text(nx, y3 + 46, "run it again to resume", "ann", "start")

    # Callout, in the free space of the YOU column between steps 4 and 12.
    lines = ["The first device writes", "the LiveSync settings of", "the vault. The bridge",
             "reads them. If the bridge", "connects first, the", "settings do not match."]
    cw, ch = 330, 96 + 26 * len(lines)
    _, y4, h4, *_ = placed[3]
    _, y12, *_ = placed[11]
    cx = X["you"] - cw / 2
    cy = (y4 + h4 + y12 - 22) / 2 - ch / 2 + 11
    s.add(f'<rect class="callout" x="{cx}" y="{cy}" width="{cw}" height="{ch}"/>')
    s.add(f'<rect x="{cx}" y="{cy}" width="10" height="{ch}" fill="{CYAN}"/>')
    s.text(cx + 30, cy + 36, "WHY THE DEVICE", "big", "start")
    s.text(cx + 30, cy + 60, "COMES FIRST", "big", "start")
    for i, line in enumerate(lines):
        s.text(cx + 30, cy + 98 + 26 * i, line, "lab", "start")
    return s


def main():
    os.makedirs(OUT, exist_ok=True)
    for fn, mk in (("01-system.svg", sheet1), ("02-setup-sequence.svg", sheet2), ("03-add-vault.svg", sheet3)):
        with open(os.path.join(OUT, fn), "w", encoding="utf-8", newline="\n") as f:
            f.write(mk().render())
        print(os.path.join("docs", "blueprints", fn))


if __name__ == "__main__":
    main()
