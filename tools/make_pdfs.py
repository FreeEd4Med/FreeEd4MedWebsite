#!/usr/bin/env python3
"""Simple single-page PDF generator for small text files.

Copyright (c) 2025 FreeEd4Med

This tool is released under the MIT License. See /LICENSE at the repository root.

This is a tiny helper to create readable PDF downloads for short textual assets.
It uses the standard PDF Type1 font Helvetica (no embedding) and writes lines top-down.
Not a full featured renderer, but good for short plain text documents (checklist, guides).
"""
import sys, os

def escape_paren(s):
    return s.replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')

def create_pdf_from_text(text: str, dest: str, title: str = 'Document'):
    # Normalize to ASCII-ish (replace common unicode dashes and ellipses)
    replacements = {
        '\u2014': '-', '\u2013': '-', '\u2018': "'", '\u2019': "'",
        '\u201c': '"', '\u201d': '"', '\u2026': '...'
    }
    for k,v in replacements.items():
        text = text.replace(k, v)

    lines = text.splitlines()
    # PDF objects
    objects = []

    # Header
    # We'll create objects: 1 Catalog, 2 Pages, 3 Page, 4 Font, 5 Content stream

    # Content stream: set font and draw lines
    content_lines = []
    content_lines.append('BT')
    content_lines.append('/F1 12 Tf')
    # Start at 760 and decrement by 14 per line
    y = 760
    x = 50
    for line in lines:
        # trim long lines
        safe = escape_paren(line)
        content_lines.append(f'{x} {y} Td ({safe}) Tj')
        content_lines.append('0 -14 Td')
        y -= 14
    content_lines.append('ET')
    content = '\n'.join(content_lines).encode('latin-1', errors='replace')

    # Create simple PDF
    # Build objects
    objs = []
    objs.append(('1 0 obj', b'<< /Type /Catalog /Pages 2 0 R >>'))
    objs.append(('2 0 obj', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>'))
    page_dict = b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>'
    objs.append(('3 0 obj', page_dict))
    font_dict = b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    objs.append(('4 0 obj', font_dict))

    # content stream object
    stream = b'stream\n' + content + b'\nendstream'
    objs.append(('5 0 obj', b'<< /Length ' + str(len(content)).encode('ascii') + b' >>\n' + stream))

    # now write PDF with cross ref
    pdf_lines = []
    pdf_lines.append(b'%PDF-1.4')
    xref_positions = []
    pos = 0
    for hdr, body in objs:
        xref_positions.append(pos)
        hdr_b = hdr.encode('ascii') if isinstance(hdr, str) else hdr
        block = (hdr_b + b'\n' + body + b'\nendobj\n')
        pdf_lines.append(block)
        pos += len(block)

    # assemble body
    pdf_content = b'\n'.join(pdf_lines)

    # compute offsets
    offsets = []
    cur = len(b'%PDF-1.4\n')
    for hdr, body in objs:
        offsets.append(cur)
        hdr_b = hdr.encode('ascii') if isinstance(hdr, str) else hdr
        block = (hdr_b + b'\n' + body + b'\nendobj\n')
        cur += len(block)

    xref_start = cur
    # xref table
    xref = []
    xref.append(b'xref')
    xref.append(b'0 %d' % (len(objs)+1))
    xref.append(b'0000000000 65535 f ')  # object 0
    for off in offsets:
        xref.append(b'%010d 00000 n ' % off)

    # trailer
    trailer = b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % ((len(objs)+1), xref_start)

    out = b'%PDF-1.4\n' + b''.join([(hdr.encode('ascii') if isinstance(hdr, str) else hdr) + b'\n' + body + b'\nendobj\n' for hdr, body in objs]) + b''.join(xref) + b'\n' + trailer

    # Write file
    with open(dest, 'wb') as f:
        f.write(out)

if __name__ == '__main__':
    # expecting pairs: input -> output
    # default behaviors when called with no args
    if len(sys.argv) == 3:
        src, dest = sys.argv[1:3]
        if not os.path.exists(src):
            print('Source not found', src); sys.exit(2)
        with open(src, 'r', encoding='utf-8') as fh:
            txt = fh.read()
        create_pdf_from_text(txt, dest, title=os.path.basename(dest))
        print('Wrote', dest)
    else:
        print('Usage: make_pdfs.py input.txt output.pdf')
