"""iOS uygulamasının içine konacak site klasörünü hazırlar (derleme sırasında çalışır).

  python3 ios/site.py --html index.html --out ios/gen/Uygulama/site \
      [--fonts-css yol/fonts.css --fonts-dir yol/fonts] [--copy dosya ...]

- Sayfa olduğu gibi kopyalanır; Google Fonts bağlantıları varsa kaldırılır ve uygulamanın
  kendi taşıdığı yazı tipleri (fonts.css + fonts/) bağlanır, böylece yazılar internetsiz de görünür.
- Yalnızca web ve Android'de olan bölümler iOS kopyasından tamamen çıkarılır (index.html ve
  kopyalanan .html dosyalarında). Bu bölümler şu işaretlerin arasındadır:
      /*android:start*/ ... /*android:end*/        (CSS ve JavaScript içinde)
      <!--android:start--> ... <!--android:end-->  (HTML içinde)
  Bir bölüm hiç gizlenmez: iOS'a giden dosyada yer almaz. İşaretler eşleşmezse derleme durur.
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

ISARETLER = [("/*android:start*/", "/*android:end*/"), ("<!--android:start-->", "<!--android:end-->")]


def ios_kopyasi(metin, ad):
    """İşaretli bölümleri çıkarır; açılış/kapanış sayısı tutmazsa ya da iç içe ise hata verir."""
    for bas, son in ISARETLER:
        if metin.count(bas) != metin.count(son):
            raise SystemExit(f"{ad}: {bas} ve {son} sayısı eşleşmiyor")
        parcalar, i = [], 0
        while True:
            s = metin.find(bas, i)
            if s < 0:
                break
            e = metin.find(son, s)
            if e < 0 or metin.find(bas, s + len(bas), e) >= 0:
                raise SystemExit(f"{ad}: {bas} bölümü düzgün kapanmıyor")
            parcalar.append(metin[i:s])
            i = e + len(son)
        metin = "".join(parcalar) + metin[i:]
    for bas, son in ISARETLER:
        if bas in metin or son in metin:
            raise SystemExit(f"{ad}: işaret kaldı")
    return metin


out = Path(a.out)
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)

html = ios_kopyasi(Path(a.html).read_text(encoding="utf-8"), a.html)
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
    elif p.is_file() and p.suffix.lower() in (".html", ".htm"):
        (out / p.name).write_text(ios_kopyasi(p.read_text(encoding="utf-8"), item), encoding="utf-8")
    elif p.exists():
        shutil.copy(p, out / p.name)
    else:
        raise SystemExit(f"bulunamadı: {item}")
print(f"{out}: {sum(1 for _ in out.rglob('*'))} dosya")
