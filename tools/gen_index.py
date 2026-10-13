"""Generate the ReaPack index for the free Panchu Scripts.

Everything is read out of each script's own ReaPack header, so the index can
never disagree with what is actually in the files. The previous hand-written
index drifted to the point of declaring 13 sources for a package that had 20,
and nothing noticed until users did.

Usage:
    python tools/gen_index.py [branch]      default branch: master
"""
import datetime
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "index.xml"

# Each entry is a folder holding single-file scripts, and the ReaPack
# category they appear under in the package browser. The folder name has no
# spaces on purpose: spaces become %20 in every source URL, which is one more
# thing to get wrong on a rename.
CATEGORIES = [
    ("QualityOfLife", "Quality of Life"),
]

BRANCH = sys.argv[1] if len(sys.argv) > 1 else "master"
RAW = f"https://raw.githubusercontent.com/panchuel/Panchu_Scripts/{BRANCH}/"
SITE = "https://github.com/panchuel/Panchu_Scripts"


def header_field(text, name):
    m = re.search(rf"^--@{name}\s+(.+)$", text, re.M)
    return m.group(1).strip() if m else None


def header_block(text, name):
    """A multi-line header field, e.g. @about, with its leading markers off."""
    m = re.search(rf"^--@{name}\s*$((?:\n--\s{{1,2}}.*)*)", text, re.M)
    if not m:
        return None
    lines = []
    for line in m.group(1).split("\n"):
        if not line.strip():
            continue
        lines.append(re.sub(r"^--\s{0,2}", "", line))
    return "\n".join(lines).strip()


def esc(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;")
                .replace(">", "&gt;").replace('"', "&quot;"))


stamp = datetime.date.today().isoformat() + "T00:00:00Z"
problems = []
blocks = []

for folder, category in CATEGORIES:
    d = ROOT / folder
    if not d.is_dir():
        problems.append(f"missing folder: {folder}")
        continue

    entries = []
    for script in sorted(d.glob("*.lua")):
        text = script.read_text(encoding="utf-8")

        desc = header_field(text, "description")
        version = header_field(text, "version")
        author = header_field(text, "author")
        about = header_block(text, "about")

        for label, value in (("@description", desc), ("@version", version),
                             ("@author", author)):
            if not value:
                problems.append(f"{script.name}: missing {label}")

        if not (desc and version and author):
            continue

        url = RAW + folder + "/" + script.name
        about_xml = ""
        if about:
            about_xml = (f"        <description><![CDATA[\n{about}\n"
                         f"        ]]></description>\n")

        entries.append(f"""    <reapack name="{script.name}" type="script" desc="{esc(desc)}">
      <metadata>
{about_xml}        <link rel="website">{SITE}</link>
      </metadata>
      <version name="{version}" author="{esc(author)}" time="{stamp}">
        <source file="{script.name}">{url}</source>
      </version>
    </reapack>""")

    if entries:
        blocks.append(f'  <category name="{esc(category)}">\n'
                      + "\n".join(entries) + "\n  </category>")

if problems:
    print("ABORT, nothing written:")
    for p in problems:
        print("  " + p)
    sys.exit(1)

xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
       '<index version="1" name="Panchu Scripts">\n'
       + "\n".join(blocks) + "\n</index>\n")

OUT.write_text(xml, encoding="utf-8")

count = sum(b.count("<reapack ") for b in blocks)
print(f"wrote {OUT}")
print(f"  branch:   {BRANCH}")
print(f"  packages: {count}")
for folder, category in CATEGORIES:
    for script in sorted((ROOT / folder).glob("*.lua")):
        v = header_field(script.read_text(encoding="utf-8"), "version")
        print(f"            {category} / {script.name}  v{v}")
