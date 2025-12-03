#!/usr/bin/env python3
"""Generate simple SVG thumbnails for glossary terms.

Reads `glossary.html` and finds terms in <article class="entry"> <h3> or <dt> tags.
Creates a minimal, consistent SVG for each missing term under
`assets/glossary_images/<slug>.svg`.

This script is intentionally simple and safe (text-only SVGs with gradients).
"""
import re, os, html, hashlib

ROOT = os.path.dirname(os.path.dirname(__file__))
GLOSSARY = os.path.join(ROOT, 'glossary.html')
OUT_DIR = os.path.join(ROOT, 'assets', 'glossary_images')

palette = [
    ("7a2ff5", "ff5c9c"),
    ("7a2ff5", "00e0ff"),
    ("ff9a9e", "fad0c4"),
    ("fe6b8b", "845ec2"),
    ("00c9a7", "7fdbff"),
    ("ffd166", "ff7b00"),
    ("00d4ff", "6f42c1"),
]

def slugify(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", '-', s)
    s = re.sub(r"(^-|-$)", '', s)
    return s[:60]

if not os.path.exists(GLOSSARY):
    print('glossary.html not found at', GLOSSARY); raise SystemExit(2)

with open(GLOSSARY, 'r', encoding='utf-8') as fh:
    src = fh.read()

# extract <article class="entry"> <h3>Title</h3>
titles = re.findall(r'<article[^>]*class=["\']entry["\'][^>]*>.*?<h3[^>]*>(.*?)</h3>', src, flags=re.I|re.S)
# extract dt entries
dt_titles = re.findall(r'<dt[^>]*>(.*?)</dt>', src, flags=re.I|re.S)

all_titles = []
for t in titles + dt_titles:
    clean = html.unescape(re.sub(r'<[^>]+>', '', t)).strip()
    if clean:
        all_titles.append(clean)

# Deduplicate preserving order
seen = set(); terms = []
for t in all_titles:
    key = t.strip().lower()
    if key not in seen:
        seen.add(key); terms.append(t.strip())

os.makedirs(OUT_DIR, exist_ok=True)
created = []
for t in terms:
    s = slugify(t)
    out = os.path.join(OUT_DIR, s + '.svg')
    if os.path.exists(out):
        continue
    # choose palette by hash
    idx = int(hashlib.sha1(s.encode('utf-8')).hexdigest(), 16) % len(palette)
    a,b = palette[idx]
    title_text = (t if len(t) <= 22 else t[:19] + '...')

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">
  <defs>
    <linearGradient id="g" x1="0" x2="1">
      <stop offset="0" stop-color="#{a}"/>
      <stop offset="1" stop-color="#{b}"/>
    </linearGradient>
  </defs>
  <rect width="120" height="120" rx="14" fill="url(#g)" opacity="0.12"/>
  <g transform="translate(12,18)" fill="#fff" opacity="0.92">
    <rect x="4" y="30" width="92" height="46" rx="8" fill="#0d0d12" opacity="0.6" />
    <text x="50%" y="66" font-size="10" font-family="Arial,Helvetica,sans-serif" text-anchor="middle" fill="#ffffff">{html.escape(title_text)}</text>
  </g>
</svg>'''
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write(svg)
    created.append((t, s))

print('Found terms:', len(terms))
print('Created icons:', len(created))
for t,s in created[:20]:
    print('-', t, '->', s + '.svg')

if not created:
    print('No new files created (all icons exist).')

# exit status
if created:
    raise SystemExit(0)
else:
    raise SystemExit(0)
