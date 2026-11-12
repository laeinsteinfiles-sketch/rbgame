#!/usr/bin/env python3
"""Font files, licences and text metrics for the UI preview.

Roblox font families (rbxasset://fonts/families/<Name>.json) are mapped to
Google Fonts families. Static per-weight TTFs are downloaded on demand into
tools/uipreview/fonts/ together with each family's licence file. Families
Google does not host use a stand-in (see STAND_INS / fonts/README.md).

  python3 tools/uipreview/fonts.py --fetch core     # default set
  python3 tools/uipreview/fonts.py --fetch all      # every mapped family
  python3 tools/uipreview/fonts.py --list
"""
import argparse
import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FONT_DIR = HERE / "fonts"
CACHE = ROOT / "build" / "preview" / "cache"
UA = "Mozilla/4.0"  # an old UA makes the CSS API serve TrueType (IE8 would get EOT)
WEIGHTS = "300,400,500,600,700,800,900"
EMOJI_URL = "https://raw.githubusercontent.com/googlefonts/noto-emoji/v2.051/fonts/NotoColorEmoji.ttf"
SYSTEM_EMOJI = ["/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"]
SYSTEM_FALLBACK = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]

# Roblox family -> (Google Fonts family, licence path in github.com/google/fonts)
FAMILIES = {
    "LegacyArial": ("Arimo", "ofl/arimo/OFL.txt"),
    "Arial": ("Arimo", "ofl/arimo/OFL.txt"),
    "Arimo": ("Arimo", "ofl/arimo/OFL.txt"),
    "AccanthisADFStd": ("Bodoni Moda", "ofl/bodonimoda/OFL.txt"),
    "AmaticSC": ("Amatic SC", "ofl/amaticsc/OFL.txt"),
    "Balthazar": ("Balthazar", "ofl/balthazar/OFL.txt"),
    "Bangers": ("Bangers", "ofl/bangers/OFL.txt"),
    "BuilderSans": ("Montserrat", "ofl/montserrat/OFL.txt"),
    "BuilderExtended": ("Montserrat", "ofl/montserrat/OFL.txt"),
    "BuilderMono": ("Roboto Mono", "ofl/robotomono/OFL.txt"),
    "GothamSSm": ("Montserrat", "ofl/montserrat/OFL.txt"),
    "ComicNeueAngular": ("Comic Neue", "ofl/comicneue/OFL.txt"),
    "Creepster": ("Creepster", "ofl/creepster/OFL.txt"),
    "DenkOne": ("Denk One", "ofl/denkone/OFL.txt"),
    "Fondamento": ("Fondamento", "ofl/fondamento/OFL.txt"),
    "FredokaOne": ("Fredoka One", "ofl/fredoka/OFL.txt"),
    "GrenzeGotisch": ("Grenze Gotisch", "ofl/grenzegotisch/OFL.txt"),
    "Guru": ("EB Garamond", "ofl/ebgaramond/OFL.txt"),
    "HighwayGothic": ("Roboto Condensed", "ofl/robotocondensed/OFL.txt"),
    "Inconsolata": ("Inconsolata", "ofl/inconsolata/OFL.txt"),
    "IndieFlower": ("Indie Flower", "ofl/indieflower/OFL.txt"),
    "JosefinSans": ("Josefin Sans", "ofl/josefinsans/OFL.txt"),
    "Jura": ("Jura", "ofl/jura/OFL.txt"),
    "Kalam": ("Kalam", "ofl/kalam/OFL.txt"),
    "LuckiestGuy": ("Luckiest Guy", "apache/luckiestguy/LICENSE.txt"),
    "Merriweather": ("Merriweather", "ofl/merriweather/OFL.txt"),
    "Michroma": ("Michroma", "ofl/michroma/OFL.txt"),
    "Montserrat": ("Montserrat", "ofl/montserrat/OFL.txt"),
    "Nunito": ("Nunito", "ofl/nunito/OFL.txt"),
    "Oswald": ("Oswald", "ofl/oswald/OFL.txt"),
    "PatrickHand": ("Patrick Hand", "ofl/patrickhand/OFL.txt"),
    "PermanentMarker": ("Permanent Marker", "apache/permanentmarker/LICENSE.txt"),
    "PressStart2P": ("Press Start 2P", "ofl/pressstart2p/OFL.txt"),
    "Roboto": ("Roboto", "ofl/roboto/OFL.txt"),
    "RobotoCondensed": ("Roboto Condensed", "ofl/robotocondensed/OFL.txt"),
    "RobotoMono": ("Roboto Mono", "ofl/robotomono/OFL.txt"),
    "RomanAntique": ("IM Fell English", "ofl/imfellenglish/OFL.txt"),
    "Sarpanch": ("Sarpanch", "ofl/sarpanch/OFL.txt"),
    "SourceSansPro": ("Source Sans 3", "ofl/sourcesans3/OFL.txt"),
    "SpecialElite": ("Special Elite", "apache/specialelite/LICENSE.txt"),
    "TitilliumWeb": ("Titillium Web", "ofl/titilliumweb/OFL.txt"),
    "Ubuntu": ("Ubuntu", "ufl/ubuntu/UFL.txt"),
    "Zekton": ("Orbitron", "ofl/orbitron/OFL.txt"),
}
STAND_INS = {k for k, (g, _) in FAMILIES.items() if g.replace(" ", "") != k}
CORE = ["LegacyArial", "FredokaOne", "LuckiestGuy", "Nunito", "Montserrat", "Roboto", "Ubuntu",
        "Bangers", "Oswald", "Merriweather", "SourceSansPro"]
DEFAULT_FAMILY = "LegacyArial"

# Characters measured for the Luau-side text metrics (everything else uses
# the face's average advance, or 1em for wide/CJK, EMOJI_ADVANCE for emoji).
MEASURED = [chr(c) for c in range(32, 127)] + [chr(c) for c in range(160, 256)] + list(
    "•…–—‘’“”×÷€₹←→↑↓✓✔✕✖★☆♥♦♣♠·⋅►▶◀▲▼■□●○◆◇")
EMOJI_ADVANCE = 1.12  # em


def google_slug(family):
    return family.replace(" ", "")


def face_path(gfamily, weight):
    return FONT_DIR / ("%s-%d.ttf" % (google_slug(gfamily), weight))


def available_faces():
    """{google_slug: {weight: path}} for downloaded TTFs."""
    faces = {}
    if FONT_DIR.exists():
        for p in FONT_DIR.glob("*.ttf"):
            m = re.match(r"^(.+)-(\d{3})\.ttf$", p.name)
            if m:
                faces.setdefault(m.group(1), {})[int(m.group(2))] = p
    return faces


def _get(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def fetch_family(roblox_family, quiet=False):
    gfamily, lic = FAMILIES[roblox_family]
    slug = google_slug(gfamily)
    if available_faces().get(slug):
        return True
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    css_url = "https://fonts.googleapis.com/css?family=%s:%s" % (urllib.parse.quote_plus(gfamily), WEIGHTS)
    try:
        css = _get(css_url).decode()
    except Exception as e:  # noqa: BLE001 - network is optional
        if not quiet:
            print("  font fetch failed for %s: %s" % (gfamily, e), file=sys.stderr)
        return False
    got = 0
    for block in re.findall(r"@font-face\s*{(.*?)}", css, re.S):
        if "font-style: italic" in block:
            continue
        w = re.search(r"font-weight:\s*(\d+)", block)
        u = re.search(r"url\((https://[^)]+\.ttf)\)", block)
        if not (w and u):
            continue
        face_path(gfamily, int(w.group(1))).write_bytes(_get(u.group(1)))
        got += 1
    lic_file = FONT_DIR / ("%s.%s" % (slug, "LICENSE.txt"))
    if not lic_file.exists():
        try:
            lic_file.write_bytes(_get("https://raw.githubusercontent.com/google/fonts/main/" + lic))
        except Exception:  # noqa: BLE001
            lic_file.write_text("See https://github.com/google/fonts/tree/main/%s\n" % lic.rsplit("/", 1)[0])
    if not quiet:
        print("  fetched %s (%d weights) for %s" % (gfamily, got, roblox_family))
    return got > 0


def emoji_font(download=True):
    local = FONT_DIR / "NotoColorEmoji.ttf"
    if local.exists():
        return local
    for p in SYSTEM_EMOJI:
        if pathlib.Path(p).exists():
            return pathlib.Path(p)
    if not download:
        return None
    try:
        FONT_DIR.mkdir(parents=True, exist_ok=True)
        print("  fetching Noto Color Emoji (~10 MB)")
        local.write_bytes(_get(EMOJI_URL, timeout=120))
        (FONT_DIR / "NotoColorEmoji.LICENSE.txt").write_bytes(
            _get("https://raw.githubusercontent.com/googlefonts/noto-emoji/v2.051/fonts/LICENSE"))
        return local
    except Exception as e:  # noqa: BLE001
        print("  emoji font unavailable: %s" % e, file=sys.stderr)
        return None


def fallback_fonts():
    return [pathlib.Path(p) for p in SYSTEM_FALLBACK if pathlib.Path(p).exists()]


FAMILY_RE = [
    re.compile(r"fonts/families/(\w+)\.json"),
    re.compile(r"Font\.fromName\(\s*[\"'](\w+)[\"']"),
]
ENUM_RE = re.compile(r"Enum\.Font\.(\w+)")
ENUM_TO_FAMILY = {
    "Legacy": "LegacyArial", "Arial": "Arial", "ArialBold": "Arial", "SourceSans": "SourceSansPro",
    "SourceSansBold": "SourceSansPro", "SourceSansSemibold": "SourceSansPro", "SourceSansLight": "SourceSansPro",
    "SourceSansItalic": "SourceSansPro", "Bodoni": "AccanthisADFStd", "Garamond": "Guru", "Cartoon": "ComicNeueAngular",
    "Code": "Inconsolata", "Highway": "HighwayGothic", "SciFi": "Zekton", "Arcade": "PressStart2P",
    "Fantasy": "Balthazar", "Antique": "RomanAntique", "Gotham": "GothamSSm", "GothamMedium": "GothamSSm",
    "GothamBold": "GothamSSm", "GothamBlack": "GothamSSm", "AmaticSC": "AmaticSC", "Bangers": "Bangers",
    "Creepster": "Creepster", "DenkOne": "DenkOne", "Fondamento": "Fondamento", "FredokaOne": "FredokaOne",
    "GrenzeGotisch": "GrenzeGotisch", "IndieFlower": "IndieFlower", "JosefinSans": "JosefinSans", "Jura": "Jura",
    "Kalam": "Kalam", "LuckiestGuy": "LuckiestGuy", "Merriweather": "Merriweather", "Michroma": "Michroma",
    "Nunito": "Nunito", "Oswald": "Oswald", "PatrickHand": "PatrickHand", "PermanentMarker": "PermanentMarker",
    "Roboto": "Roboto", "RobotoCondensed": "RobotoCondensed", "RobotoMono": "RobotoMono", "Sarpanch": "Sarpanch",
    "SpecialElite": "SpecialElite", "TitilliumWeb": "TitilliumWeb", "Ubuntu": "Ubuntu", "BuilderSans": "BuilderSans",
    "BuilderSansMedium": "BuilderSans", "BuilderSansBold": "BuilderSans", "BuilderSansExtraBold": "BuilderSans",
    "Arimo": "Arimo", "ArimoBold": "Arimo",
}


def families_in_text(text):
    found = set()
    for rx in FAMILY_RE:
        found.update(m for m in rx.findall(text) if m in FAMILIES)
    found.update(ENUM_TO_FAMILY[m] for m in ENUM_RE.findall(text) if m in ENUM_TO_FAMILY)
    return found


def ensure_families(families, quiet=False):
    """Download any mapped family not present yet. Returns names that failed."""
    have = available_faces()
    missing = sorted({f for f in families if f in FAMILIES and google_slug(FAMILIES[f][0]) not in have})
    failed = []
    for f in missing:
        if not fetch_family(f, quiet=quiet):
            failed.append(f)
    return failed


# ---------------------------------------------------------------- metrics

def compute_metrics():
    """Per-face advance widths (per 1000 em) for MEASURED chars + vertical metrics.

    Cached in build/preview/cache/fontmetrics.json keyed by the font files.
    """
    from PIL import ImageFont

    faces = available_faces()
    key = sorted("%s:%d:%d" % (p.name, p.stat().st_size, int(p.stat().st_mtime)) for ws in faces.values() for p in ws.values())
    cache_file = CACHE / "fontmetrics.json"
    if cache_file.exists():
        try:
            cached = json.loads(cache_file.read_text())
            if cached.get("key") == key:
                return cached["faces"]
        except Exception:  # noqa: BLE001
            pass
    out = {}
    for slug, weights in faces.items():
        for w, path in weights.items():
            f = ImageFont.truetype(str(path), 1000)
            adv = [int(round(f.getlength(ch))) for ch in MEASURED]
            letters = [f.getlength(ch) for ch in "abcdefghijklmnopqrstuvwxyzetaoinshrdlu"]
            asc, desc = f.getmetrics()
            out["%s-%d" % (slug, w)] = {
                "adv": adv, "avg": int(round(sum(letters) / len(letters))),
                "asc": asc, "desc": desc, "path": str(path.relative_to(HERE)),
            }
    CACHE.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(json.dumps({"key": key, "faces": out}))
    return out


def resolve_face(roblox_family, weight, faces=None):
    """(face_key, path) for a Roblox family + numeric weight, nearest weight wins."""
    faces = faces if faces is not None else available_faces()
    gfam = FAMILIES.get(roblox_family, FAMILIES[DEFAULT_FAMILY])[0]
    slug = google_slug(gfam)
    ws = faces.get(slug)
    if not ws:
        slug = google_slug(FAMILIES[DEFAULT_FAMILY][0])
        ws = faces.get(slug)
        if not ws:
            return None, None
    best = min(ws, key=lambda x: (abs(x - weight), -x))
    return "%s-%d" % (slug, best), ws[best]


def luau_metrics_table():
    """Luau source for the runtime: face table + per-family weight map."""
    faces = available_faces()
    metrics = compute_metrics()
    lines = ["{", "measured = %s," % lua_str("".join(MEASURED)), "emojiAdvance = %s," % EMOJI_ADVANCE, "faces = {"]
    for key, m in sorted(metrics.items()):
        lines.append("[%s] = { avg = %d, asc = %d, desc = %d, adv = {%s} }," % (
            lua_str(key), m["avg"], m["asc"], m["desc"], ",".join(str(a) for a in m["adv"])))
    lines.append("},")
    lines.append("families = {")
    for fam, (gfam, _) in sorted(FAMILIES.items()):
        slug = google_slug(gfam)
        ws = sorted(faces.get(slug, {}))
        if ws:
            lines.append("[%s] = { slug = %s, weights = {%s} }," % (lua_str(fam), lua_str(slug), ",".join(str(w) for w in ws)))
    lines.append("},")
    lines.append("default = %s," % lua_str(DEFAULT_FAMILY))
    lines.append("}")
    return "\n".join(lines)


def lua_str(s):
    return '"' + "".join(
        ("\\" + c) if c in '"\\' else ("\\n" if c == "\n" else c) for c in s) + '"'


def write_readme_index():
    """Regenerate the licence table section of fonts/README.md."""
    rows = []
    faces = available_faces()
    seen = set()
    for fam, (gfam, lic) in sorted(FAMILIES.items()):
        slug = google_slug(gfam)
        status = "downloaded" if faces.get(slug) else "on demand"
        kind = lic.split("/")[0]
        lic_name = {"ofl": "SIL Open Font License 1.1", "apache": "Apache License 2.0", "ufl": "Ubuntu Font Licence 1.0"}[kind]
        rows.append("| %s | %s%s | %s | %s |" % (fam, gfam, " (stand-in)" if fam in STAND_INS else "", lic_name, status))
        seen.add(slug)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", choices=["core", "all", "emoji"], help="download font files")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.fetch:
        fams = CORE if args.fetch == "core" else list(FAMILIES) if args.fetch == "all" else []
        failed = ensure_families(fams)
        emoji_font(download=True)
        if failed:
            print("failed:", ", ".join(failed))
    if args.list:
        for row in write_readme_index():
            print(row)


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT / "build" / "preview" / ".pydeps"))
    main()
