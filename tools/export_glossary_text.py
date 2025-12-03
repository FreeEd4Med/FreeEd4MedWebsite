#!/usr/bin/env python3
"""Export the glossary HTML to a readable plain-text file.

Copyright (c) 2025 FreeEd4Med

This tool is released under the MIT License. See /LICENSE at the repository root.

This script extracts the <main> section of `glossary.html`, converts headings
and definition lists to plain text and writes to assets/glossary.txt for
PDF conversion with `make_pdfs.py`.
"""
import re, html, sys, os

ROOT = os.path.dirname(os.path.dirname(__file__))
GLOSS_HTML = os.path.join(ROOT, 'glossary.html')
OUT_TXT = os.path.join(ROOT, 'assets', 'glossary.txt')

def extract_main(htmltext):
    m = re.search(r"<main[^>]*>(.*?)</main>", htmltext, re.S|re.I)
    return m.group(1) if m else htmltext

def strip_tags(s):
    # collapse tags to newlines for block elements
    s = re.sub(r'<(h[12-6]|p|div|section|article|li|dt|dd|br)[^>]*>', '\n', s, flags=re.I)
    # remove remaining tags
    s = re.sub(r'<[^>]+>', '', s)
    s = html.unescape(s)
    # normalize spaces
    s = re.sub(r'\s+',' ', s)
    s = s.strip()
    return s

def format_text(main_html):
    # Replace dt/dd pairs into a clear format
    # Make sure newlines are preserved for readability.
    # Convert headings h2/h3 into labelled sections
    text = main_html
    # Mark h2 and h3
    text = re.sub(r'<h2[^>]*>(.*?)</h2>', r'\n\n== \1 ==\n\n', text, flags=re.I|re.S)
    text = re.sub(r'<h3[^>]*>(.*?)</h3>', r'\n\n-- \1 --\n', text, flags=re.I|re.S)
    # convert dt/dd to lines
    text = re.sub(r'<dt[^>]*>(.*?)</dt>\s*<dd[^>]*>(.*?)</dd>', r'\n\1:\n  \2\n', text, flags=re.I|re.S)
    # also handle the flattened format where glossary items are article.entry
    # entries (created by the client-side transform) — convert <article class="entry"><h3>Term</h3><p>Definition</p></article>
    text = re.sub(r'<article[^>]*class=["\']?entry["\']?[^>]*>.*?<h3[^>]*>(.*?)</h3>.*?<p[^>]*>(.*?)</p>.*?</article>',
                  r'\n\1:\n  \2\n', text, flags=re.I|re.S)

    # remove any leftover html tags
    out = strip_tags(text)
    # tidy up multiple newlines
    out = re.sub(r'\n\s+','\n', out)
    out = re.sub(r'\n{3,}', '\n\n', out)
    return out

def main():
    if not os.path.exists(GLOSS_HTML):
        print('glossary.html not found at', GLOSS_HTML, file=sys.stderr); sys.exit(2)
    with open(GLOSS_HTML, 'r', encoding='utf-8') as fh:
        htmlsrc = fh.read()
    main_html = extract_main(htmlsrc)
    text = format_text(main_html)
    # prepend header
    title = 'FreeEd4Med — Glossary (mixing, mastering, clinical audio)'
    out = title + '\n' + ('='*len(title)) + '\n\n' + text + '\n'
    os.makedirs(os.path.dirname(OUT_TXT), exist_ok=True)
    with open(OUT_TXT, 'w', encoding='utf-8') as fh:
        fh.write(out)
    print('Wrote', OUT_TXT)

if __name__ == '__main__':
    main()
