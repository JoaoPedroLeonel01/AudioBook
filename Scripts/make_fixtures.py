#!/usr/bin/env python3
"""Gera EPUBs sintéticos usados pelos testes (AudioBookTests/Fixtures)."""
import sys, zipfile, os

out = sys.argv[1] if len(sys.argv) > 1 else "AudioBookTests/Fixtures"
os.makedirs(out, exist_ok=True)

CONTAINER = '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'

def xhtml(body, title="t"):
    return f'<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>{title}</title><style>p{{color:red}}</style></head><body>{body}</body></html>'

def epub(path, opf, files, extra=None):
    with zipfile.ZipFile(os.path.join(out, path), "w") as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", CONTAINER, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        for name, data in files.items():
            z.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)
        for name, data in (extra or {}).items():
            z.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)

# PNG 2x3 válido gerado em tempo de execução
import struct, zlib
def _chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
_raw = b"".join(b"\x00" + b"\xc8\x40\x40" * 2 for _ in range(3))
PNG = b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 3, 8, 2, 0, 0, 0)) + _chunk(b"IDAT", zlib.compress(_raw)) + _chunk(b"IEND", b"")

# EPUB 3 com nav, ordem da spine diferente da ordem do manifest e capítulo vazio
opf3 = '''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Livro de Teste</dc:title><dc:creator>Ana Silva</dc:creator><dc:creator>Bruno Costa</dc:creator><dc:language>pt-BR</dc:language><dc:identifier id="id">x</dc:identifier></metadata>
<manifest><item id="c2" href="text/cap2.xhtml" media-type="application/xhtml+xml"/><item id="c1" href="text/cap1.xhtml" media-type="application/xhtml+xml"/><item id="empty" href="text/vazio.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="cover" href="images/capa.png" media-type="image/png" properties="cover-image"/></manifest>
<spine><itemref idref="c1"/><itemref idref="empty"/><itemref idref="c2"/></spine></package>'''
nav = xhtml('<nav epub:type="toc"><ol><li><a href="text/cap1.xhtml">Primeiro Capítulo</a></li><li><a href="text/cap2.xhtml#s1">Segundo &amp; Final</a></li></ol></nav>')
cap1 = xhtml('<h1>Primeiro Capítulo</h1><p>Era uma vez&nbsp;um   texto  com <em>ênfase</em> e&#233;ntidades &mdash; &quot;aspas&quot;.</p><p>Segundo parágrafo.<br/>Linha nova.</p><script>alert(1)</script><ul><li>Item um</li><li>Item dois</li></ul><p>* * *</p>')
cap2 = xhtml('<h2>Segundo</h2><p>Texto do segundo capítulo.<a epub:type="noteref" href="#n1">1</a></p><div epub:type="pagebreak">99</div><nav><a href="x">menu</a></nav>')
vazio = xhtml('<img src="x.png"/>')
epub("sample.epub", opf3, {"OEBPS/nav.xhtml": nav, "OEBPS/text/cap1.xhtml": cap1, "OEBPS/text/cap2.xhtml": cap2, "OEBPS/text/vazio.xhtml": vazio, "OEBPS/images/capa.png": PNG})

# EPUB 2 com NCX, sem metadados de autor, capa via <meta name="cover">
opf2 = '''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf"><dc:title>Livro NCX</dc:title><meta name="cover" content="img"/></metadata>
<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="a" href="a.html" media-type="application/xhtml+xml"/><item id="b" href="b.html" media-type="application/xhtml+xml"/><item id="img" href="c.png" media-type="image/png"/></manifest>
<spine toc="ncx"><itemref idref="a"/><itemref idref="b"/></spine></package>'''
ncx = '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint id="1"><navLabel><text>Parte A</text></navLabel><content src="a.html"/></navPoint><navPoint id="2"><navLabel><text>Parte B</text></navLabel><content src="b.html#x"/></navPoint></navMap></ncx>'
epub("ncx.epub", opf2, {"OEBPS/toc.ncx": ncx, "OEBPS/a.html": xhtml("<p>Conteúdo A.</p>"), "OEBPS/b.html": xhtml("<p>Conteúdo B.</p>"), "OEBPS/c.png": PNG})

# Sem sumário: títulos vêm dos cabeçalhos / fallback
opfn = '''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Sem Sumário</dc:title></metadata>
<manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>'''
epub("notoc.epub", opfn, {"OEBPS/a.xhtml": xhtml("<h1>Introdução</h1><p>Olá.</p>"), "OEBPS/b.xhtml": xhtml("<p>Sem cabeçalho.</p>")})

# Somente capítulos vazios
epub("empty.epub", opfn, {"OEBPS/a.xhtml": xhtml("<p> </p>"), "OEBPS/b.xhtml": xhtml("<img src='x'/>")})

# DRM: encryption.xml cifrando conteúdo
enc = '<?xml version="1.0"?><encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/><enc:CipherData><enc:CipherReference URI="OEBPS/a.xhtml"/></enc:CipherData></enc:EncryptedData></encryption>'
epub("drm.epub", opfn, {"OEBPS/a.xhtml": "binario", "OEBPS/b.xhtml": xhtml("<p>x</p>"), "META-INF/encryption.xml": enc})

# Ofuscação de fontes não é DRM
encfont = enc.replace("http://www.w3.org/2001/04/xmlenc#aes128-cbc", "http://www.idpf.org/2008/embedding").replace("OEBPS/a.xhtml", "OEBPS/f.otf")
epub("fontobf.epub", opfn, {"OEBPS/a.xhtml": xhtml("<h1>Introdução</h1><p>Olá.</p>"), "OEBPS/b.xhtml": xhtml("<p>x</p>"), "OEBPS/f.otf": "font", "META-INF/encryption.xml": encfont})

# Arquivos inválidos
open(os.path.join(out, "notzip.epub"), "w").write("isto não é um zip")
with zipfile.ZipFile(os.path.join(out, "nocontainer.epub"), "w") as z:
    z.writestr("hello.txt", "x")
