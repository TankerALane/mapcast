"""Render the Mapcast logo SVGs to PNG/ICO with headless Chrome (or Edge).

Usage: python assets/logo/render.py
Outputs go to assets/logo/export/, plus the addon icon and the companion .ico.
"""
import os, struct, subprocess, sys, tempfile, pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = HERE / "export"
BROWSERS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
]

def browser():
    for b in BROWSERS:
        if os.path.exists(b):
            return b
    sys.exit("Chrome or Edge not found")

def render(svg, w, h, out):
    """Render svg (path) to a w x h PNG with a transparent background."""
    html = f"""<!doctype html><html><head><style>
    html,body{{margin:0;padding:0;background:transparent;overflow:hidden}}
    img{{display:block;width:{w}px;height:{h}px}}</style></head>
    <body><img src="{pathlib.Path(svg).as_uri()}"></body></html>"""
    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / "page.html"
        page.write_text(html, encoding="utf-8")
        subprocess.run([browser(), "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--allow-file-access-from-files", "--force-device-scale-factor=1",
                        "--default-background-color=00000000",
                        f"--window-size={w},{h}", f"--screenshot={out}", page.as_uri()],
                       check=True, capture_output=True)
    print("wrote", out)

def make_ico(pngs, out):
    """Pack PNG images into a .ico (PNG-compressed entries, Vista+)."""
    entries, blobs = [], []
    offset = 6 + 16 * len(pngs)
    for size, path in pngs:
        data = pathlib.Path(path).read_bytes()
        dim = 0 if size >= 256 else size
        entries.append(struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset))
        blobs.append(data)
        offset += len(data)
    with open(out, "wb") as f:
        f.write(struct.pack("<HHH", 0, 1, len(pngs)))
        for e in entries: f.write(e)
        for b in blobs: f.write(b)
    print("wrote", out)

def main():
    OUT.mkdir(exist_ok=True)
    mark = HERE / "mapcast-mark.svg"
    comp = HERE / "mapcast-companion-mark.svg"
    render(mark, 256, 256, OUT / "mapcast-curseforge-256.png")
    render(mark, 512, 512, OUT / "mapcast-512.png")
    render(HERE / "social-preview.svg", 1280, 640, OUT / "mapcast-social-1280x640.png")
    render(comp, 256, 256, OUT / "mapcast-companion-256.png")
    # In-game icon (TOC IconTexture + popup). WoW textures must be power-of-two sized.
    render(mark, 64, 64, ROOT / "addon" / "Mapcast" / "Media" / "Mapcast.png")
    # Companion .ico, each size rendered natively for crisp small icons.
    sizes = [16, 24, 32, 48, 64, 128, 256]
    tmp = OUT / "ico"
    tmp.mkdir(exist_ok=True)
    pngs = []
    for s in sizes:
        p = tmp / f"companion-{s}.png"
        render(comp, s, s, p)
        pngs.append((s, p))
    ico = ROOT / "companion" / "MapcastCompanion" / "Assets" / "MapcastCompanion.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    make_ico(pngs, ico)

if __name__ == "__main__":
    main()
