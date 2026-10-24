"""iOS'a giden site kopyasını denetler (GitHub Actions'ta ios/hazirla.sh'den sonra çalışır).

  python3 ios/denetle.py ios/gen/DepremAtlasi/site ios/project.yml

Derlemeyi durdurur, eğer:
- kopyada yalnızca web/Android'de olan deprem bildirimi bölümünden bir parça kaldıysa,
- iOS ayarlarında sayfaya CSS ile bir şey gizleyen ek CSS (ExtraCSS) varsa,
- sayfadaki satır içi betiklerden biri JavaScript olarak okunamıyorsa (node --check).
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

site = Path(sys.argv[1])
ayarlar = [Path(p) for p in sys.argv[2:]]

YASAK = [
    "acil-bildirim", "bildirim-kutu", "bildirim-ac", "bildirim-deneme", "bildirim-kapat",
    "bildirimKutusu", "bildirimAc", "bildirimDestegi", "bildirimEsik",
    '"/abone"', '"/vapid"', '"/deneme"', '"/iptal"', "/abone", "/vapid", "/iptal",
    "pushManager", "PushManager", "Notification.requestPermission", "serviceWorker",
    "Deprem olunca haber ver", "Deprem bildirimleri",
    "android:start", "android:end",
]
YASAK_AYAR = [re.compile(r"ExtraCSS"), re.compile(r"display\s*:\s*none")]

hatalar = []
sayfalar = sorted(site.rglob("*.html"))
if not (site / "index.html").is_file():
    hatalar.append(f"{site}/index.html yok")
if (site / "sw.js").exists():
    hatalar.append("sw.js iOS kopyasında olmamalı")

for f in sayfalar:
    metin = f.read_text(encoding="utf-8")
    for y in YASAK:
        if y in metin:
            hatalar.append(f"{f}: yasak ifade: {y}")
    # Satır içi betikler JavaScript olarak okunabiliyor mu?
    for i, m in enumerate(re.finditer(r"<script\b([^>]*)>(.*?)</script>", metin, re.S)):
        nit, kod = m.group(1), m.group(2)
        if "src=" in nit or ("type=" in nit and not re.search(r"type=[\"']?(text/javascript|module)", nit)):
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".mjs" if "module" in nit else ".js",
                                         delete=False, encoding="utf-8") as t:
            t.write(kod)
        r = subprocess.run(["node", "--check", t.name], capture_output=True, text=True)
        Path(t.name).unlink()
        if r.returncode != 0:
            hatalar.append(f"{f}: {i + 1}. betik okunamıyor:\n{r.stderr.strip()[:2000]}")
        else:
            print(f"{f.name}: {i + 1}. betik tamam ({len(kod)} karakter)")

for a in ayarlar:
    metin = a.read_text(encoding="utf-8", errors="replace")
    for y in YASAK_AYAR:
        if y.search(metin):
            hatalar.append(f"{a}: yasak ayar: {y.pattern}")

if hatalar:
    print("\n".join("HATA: " + h for h in hatalar))
    sys.exit(1)
print(f"Denetim tamam: {len(sayfalar)} sayfa, yasak ifade yok.")
