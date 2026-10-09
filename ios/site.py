"""iOS uygulamasının içine konacak site klasörünü hazırlar (derleme sırasında çalışır).

  python3 ios/site.py --html index.html --out ios/gen/Uygulama/site \
      [--fonts-css yol/fonts.css --fonts-dir yol/fonts] [--copy dosya ...]

- Sayfa olduğu gibi kopyalanır; Google Fonts bağlantıları varsa kaldırılır ve uygulamanın
  kendi taşıdığı yazı tipleri (fonts.css + fonts/) bağlanır, böylece yazılar internetsiz de görünür.
- --copy ile verilen dosyalar/klasörler de site klasörüne kopyalanır.
"""
import argparse
import re
import shutil
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--html", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--fonts-css")
ap.add_argument("--fonts-dir")
ap.add_argument("--copy", nargs="*", default=[])
a = ap.parse_args()

out = Path(a.out)
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)

html = Path(a.html).read_text(encoding="utf-8")
if a.fonts_css:
    links = re.compile(r'[ \t]*<link\b[^>]*fonts\.(?:googleapis|gstatic)\.com[^>]*>[ \t]*\r?\n?')
    found = links.search(html)
    html = links.sub("", html)
    tag = '<link rel="stylesheet" href="fonts.css">\n'
    html = (html[:found.start()] + tag + html[found.start():]) if found else html.replace("</head>", tag + "</head>", 1)
    shutil.copy(a.fonts_css, out / "fonts.css")
    if a.fonts_dir:
        shutil.copytree(a.fonts_dir, out / "fonts")
(out / "index.html").write_text(html, encoding="utf-8")

for item in a.copy:
    p = Path(item)
    if p.is_dir():
        shutil.copytree(p, out / p.name)
    elif p.exists():
        shutil.copy(p, out / p.name)
    else:
        raise SystemExit(f"bulunamadı: {item}")
print(f"{out}: {sum(1 for _ in out.rglob('*'))} dosya")
