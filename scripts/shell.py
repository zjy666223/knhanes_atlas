"""Build the early homepage from the application's own About panel."""
from hashlib import sha256
from html import escape
from html.parser import HTMLParser
from pathlib import Path
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"


class AboutPanel(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.depth = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "div" and attributes.get("data-value") == "About":
            self.depth = 1
            return
        if self.depth:
            self.parts.append(self.get_starttag_text())
            if tag == "div":
                self.depth += 1

    def handle_endtag(self, tag):
        if self.depth:
            if tag == "div":
                self.depth -= 1
            if self.depth:
                self.parts.append(f"</{tag}>")

    def handle_startendtag(self, tag, attrs):
        if self.depth:
            self.parts.append(self.get_starttag_text())

    def handle_data(self, data):
        if self.depth:
            self.parts.append(data)

    def handle_entityref(self, name):
        if self.depth:
            self.parts.append(f"&{name};")

    def handle_charref(self, name):
        if self.depth:
            self.parts.append(f"&#{name};")


panel = AboutPanel()
panel.feed((ROOT / "work/ui.html").read_text())
about = "".join(panel.parts)
assert "The KNHANES Phenome–Exposome Atlas" in about
about = about.replace("data-atlas-src=", "src=")
about = about.replace(' role="main"', '')
about = re.sub(r'<a href="#" onclick="[^"]*">', '<a href="#downloads">', about)
cover = SITE / "research/figures/10_研究流程.png"
with cover.open("rb") as handle:
    handle.seek(16)
    width, height = struct.unpack(">II", handle.read(8))
about = about.replace('class="study-flowchart"',
                      f'class="study-flowchart" width="{width}" height="{height}" fetchpriority="high"')

tabs = ["Browse By Phenotype", "Browse By Exposure", "Browse by Exposure Group",
        "E Catalog", "P Catalog", "Vibration of effects"]
nav = '<a href="#about" aria-current="page">About</a>'
nav += "".join(f'<a href="#atlas-loading" data-atlas-tab="{escape(tab)}">{escape(tab)}</a>' for tab in tabs)
nav += '<a href="#downloads">Downloads</a>'
names = ["associations", "exposures", "phenotypes", "joint", "network",
         "exposure_profiles", "phenotype_profiles", "vibration"]
results = "".join(f'<li><a href="research/data/{name}.csv" download>{name.replace("_", " ")}</a></li>' for name in names)
figures = json.loads((ROOT / "src/data/figures.json").read_text())
figure_links = "".join(f'<li><a href="research/{escape(item["file"], quote=True)}" download>{escape(item["title"])}</a></li>' for item in figures)
loader = (ROOT / "scripts/loader.js").read_bytes()
(SITE / "loader.js").write_bytes(loader)
values = {
    "BUILD": sha256((SITE / "app.json").read_bytes() +
                    (SITE / "shinylive/webr/packages/metadata.rds").read_bytes()).hexdigest()[:16],
    "LOADER": sha256(loader).hexdigest()[:16],
    "STYLE": (ROOT / "scripts/shell.css").read_text(),
    "ABOUT": about, "NAV": nav, "RESULTS": results, "FIGURES": figure_links,
}
page = (ROOT / "scripts/shell.html").read_text()
for key, value in values.items():
    page = page.replace(f"__{key}__", value)
assert not re.search(r"__[A-Z]+__", page)
(SITE / "index.html").write_text(page)
print(f"Early homepage: {len(page.encode()) / 1024:.1f} KiB; same study text and figures.")
