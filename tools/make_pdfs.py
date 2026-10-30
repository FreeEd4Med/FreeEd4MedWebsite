#!/usr/bin/env python3
"""Basic multi-page PDF generator for short text files.

Copyright (c) 2025 FreeEd4Med

This tool is released under the MIT License. See /LICENSE at the repository root.

This helper creates readable PDF downloads for short text assets. It uses the
standard PDF Type1 font Helvetica (no embedding), wraps lines, and writes them
top-down. It is not a full-featured Markdown or page-layout renderer.
"""
import os
import sys
import textwrap

def escape_paren(s):
    return s.replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')

def create_pdf_from_text(text: str, dest: str, title: str = 'Document'):
    replacements = {
        '\u2014': '-', '\u2013': '-', '\u2011': '-', '\u2212': '-',
        '\u2018': "'", '\u2019': "'", '\u201c': '"', '\u201d': '"',
        '\u2026': '...', '\u2022': '*', '\u00a0': ' ', '\u2264': '<=',
        '\u2265': '>=', '\u2248': '~'
    }
    for k, v in replacements.items():
        text = text.replace(k, v)

    lines = []
    for line in text.splitlines():
        if not line.strip():
            lines.append('')
        else:
            line = line.strip()
            if line.startswith('#'):
                line = line.lstrip('#').strip()
            elif line.startswith('- '):
                line = '* ' + line[2:]
            lines.extend(textwrap.wrap(line, width=86, break_long_words=False) or [''])

    page_lines = [lines[index:index + 50] for index in range(0, len(lines), 50)] or [[]]
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        None,
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ]
    page_ids = []

    for page in page_lines:
        content_lines = ['BT', '/F1 11 Tf', '50 760 Td']
        for index, line in enumerate(page):
            if index:
                content_lines.append('0 -14 Td')
            content_lines.append(f'({escape_paren(line)}) Tj')
        content_lines.append('ET')
        content = '\n'.join(content_lines).encode('latin-1', errors='replace')

        content_id = len(objects) + 1
        objects.append(
            b'<< /Length ' + str(len(content)).encode('ascii') + b' >>\nstream\n'
            + content + b'\nendstream'
        )
        page_id = len(objects) + 1
        objects.append(
            f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            f'/Resources << /Font << /F1 3 0 R >> >> /Contents {content_id} 0 R >>'.encode('ascii')
        )
        page_ids.append(page_id)

    kids = ' '.join(f'{page_id} 0 R' for page_id in page_ids)
    objects[1] = f'<< /Type /Pages /Kids [{kids}] /Count {len(page_ids)} >>'.encode('ascii')

    output = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
    offsets = [0]
    for index, body in enumerate(objects, start=1):
        offsets.append(len(output))
        output.extend(f'{index} 0 obj\n'.encode('ascii'))
        output.extend(body)
        output.extend(b'\nendobj\n')

    xref_offset = len(output)
    output.extend(f'xref\n0 {len(objects) + 1}\n'.encode('ascii'))
    output.extend(b'0000000000 65535 f\n')
    for offset in offsets[1:]:
        output.extend(f'{offset:010d} 00000 n\n'.encode('ascii'))
    output.extend(
        f'trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n'
        f'startxref\n{xref_offset}\n%%EOF\n'.encode('ascii')
    )

    with open(dest, 'wb') as pdf_file:
        pdf_file.write(output)

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
