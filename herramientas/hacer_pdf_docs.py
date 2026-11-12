#!/usr/bin/env python3
"""Convierte docs/*.md en PDF (misma línea Tukán: azul noche y amarillo).
Uso:  python3 herramientas/hacer_pdf_docs.py
Necesita: pip install markdown playwright  (y chromium de playwright)."""
import os, sys, markdown
from playwright.sync_api import sync_playwright
AQUI = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(os.path.dirname(AQUI), 'docs')
CSS = """
@page{size:A4;margin:18mm 16mm}
body{font-family:'DejaVu Sans',Arial,sans-serif;color:#14213D;font-size:11.5px;line-height:1.5}
h1{background:#14213D;color:#fff;padding:14px 18px;border-radius:10px;font-size:22px;border-bottom:5px solid #FFC93C}
h2{color:#14213D;border-left:6px solid #FFC93C;padding-left:10px;font-size:16px;margin-top:22px}
h3{color:#14213D;font-size:13px}
blockquote{background:#FFF6D6;border-left:5px solid #FFC93C;margin:12px 0;padding:6px 14px;border-radius:6px}
table{border-collapse:collapse;width:100%;margin:10px 0}th{background:#14213D;color:#fff;text-align:left}
th,td{border:1px solid #D9DEE8;padding:6px 8px;vertical-align:top}
code{background:#EEF1F6;padding:1px 4px;border-radius:4px}a{color:#14213D}
"""
def main():
    with sync_playwright() as p:
        b = p.chromium.launch(); pg = b.new_page()
        for nombre, titulo in (('PRIMEROS_PASOS_IPHONE', 'Primeros pasos en las apps de iPhone'), ('MANUAL_IPHONE', 'Manual de las apps de iPhone')):
            md = open(os.path.join(DOCS, nombre + '.md'), encoding='utf-8').read()
            html = markdown.markdown(md, extensions=['tables', 'sane_lists'])
            html = f'<!doctype html><html lang="es"><head><meta charset="utf-8"><title>{titulo}</title><style>{CSS}</style></head><body>{html}</body></html>'
            tmp = os.path.join('/tmp', nombre + '.html'); open(tmp, 'w', encoding='utf-8').write(html)
            pg.goto('file://' + tmp)
            out = os.path.join(DOCS, {'PRIMEROS_PASOS_IPHONE': 'Primeros_Pasos_iPhone.pdf', 'MANUAL_IPHONE': 'Manual_iPhone.pdf'}[nombre])
            pg.pdf(path=out, format='A4', print_background=True)
            print('listo', out)
        b.close()
main()
