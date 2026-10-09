"""Bir ilçenin mahalle sınırlarını OpenStreetMap'teki resmi sınırlarla değiştirir.

python3 araclar/osm_sinir.py osm.json index.html KADIKÖY cikti/

- osm.json: Overpass'tan "out geom" ile indirilmiş mahalle (admin_level=8) ilişkileri
- İlçenin dış sınırı ve kıyı çizgisi şimdiki veriden alınır; OSM yalnızca mahalleler arası çizgileri belirler
  (her OSM mahallesi, şimdiki mahallelerin birleşimiyle kesilir).
- Sonuç: cikti/index.html (güncellenmiş), cikti/once-sonra.png (karşılaştırma), cikti/rapor.txt
"""
import json, math, re, sys
from pathlib import Path
from shapely.geometry import LineString, Polygon, MultiPolygon
from shapely.ops import linemerge, polygonize, unary_union

osm_path, html_path, ilce, out = sys.argv[1], sys.argv[2], sys.argv[3], Path(sys.argv[4])
out.mkdir(parents=True, exist_ok=True)
html = Path(html_path).read_text(encoding="utf-8")

TR = str.maketrans("abcçdefgğhıijklmnoöprsştuüvyz", "ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ")
def buyuk(s): return s.translate(TR).upper()

def coz(s):
    a = list(map(int, s.split(","))); x = y = 0; o = []
    for i in range(0, len(a), 2):
        x += a[i]; y += a[i + 1]; o.append((x / 1e5, y / 1e5))
    return o

def kodla(coords):
    pts = [(round(x * 1e5), round(y * 1e5)) for x, y in coords]
    temiz = [pts[0]]
    for p in pts[1:]:
        if p != temiz[-1]: temiz.append(p)
    if temiz[0] != temiz[-1]: temiz.append(temiz[0])
    o = []; px = py = 0
    for x, y in temiz:
        o += [x - px, y - py]; px, py = x, y
    return ",".join(map(str, o))

def km2(poly):
    lat = poly.centroid.y
    kx, ky = 111.320 * math.cos(math.radians(lat)), 110.574
    return abs(Polygon([(x * kx, y * ky) for x, y in poly.exterior.coords]).area)

desen = re.compile(r'("anahtar":"' + re.escape(ilce) + r'/([^"]+)","ilce":"' + re.escape(ilce) +
                   r'","ad":"([^"]+)","alan":)([0-9.]+)(,"sinir":")([^"]*)(")')
eski = {m.group(3): Polygon(coz(m.group(6))).buffer(0) for m in desen.finditer(html)}
ilce_sekli = unary_union(list(eski.values())).buffer(0)

osm = json.load(open(osm_path))
yeni = {}
for e in osm["elements"]:
    ad = e["tags"].get("name", "").replace(" Mahallesi", "").strip()
    cizgiler = [LineString([(p["lon"], p["lat"]) for p in m["geometry"]])
                for m in e.get("members", []) if m.get("type") == "way" and m.get("role") in ("outer", "") and m.get("geometry")]
    alanlar = list(polygonize(linemerge(cizgiler)))
    if not alanlar: continue
    yeni[ad] = unary_union(alanlar).buffer(0)

rapor = []
for ad in eski:
    if ad not in yeni:
        rapor.append(f"{ad}: OSM'de yok, eski sınır kaldı")
kesik = {}
for ad, p in yeni.items():
    if ad not in eski:
        rapor.append(f"{ad}: uygulamada yok, atlandı"); continue
    k = p.intersection(ilce_sekli)
    if isinstance(k, MultiPolygon) or k.geom_type == "GeometryCollection":
        parcalar = [g for g in getattr(k, "geoms", []) if g.geom_type == "Polygon"]
        k = max(parcalar, key=lambda g: g.area)
    k = k.simplify(0.00002, preserve_topology=True)
    kesik[ad] = k
bosluk = ilce_sekli.difference(unary_union(list(kesik.values())))
rapor.append(f"İlçede hiçbir mahalleye düşmeyen alan: {km2(bosluk.convex_hull) if not bosluk.is_empty else 0:.3f} km² (dış kutu, üst sınır)")

def degistir(m):
    ad = m.group(3)
    if ad not in kesik: return m.group(0)
    p = kesik[ad]
    rapor.append(f"{ad}: {m.group(4)} km² -> {km2(p):.2f} km², {len(p.exterior.coords)} nokta")
    return m.group(1) + f"{km2(p):.2f}" + m.group(5) + kodla(list(p.exterior.coords)) + m.group(7)
yeni_html = desen.sub(degistir, html)
(out / "index.html").write_text(yeni_html, encoding="utf-8")
(out / "rapor.txt").write_text("\n".join(rapor), encoding="utf-8")
print("\n".join(rapor))

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
fig, axs = plt.subplots(1, 2, figsize=(22, 11))
for ax, veri, baslik in ((axs[0], eski, "Önce"), (axs[1], kesik, "Sonra (OSM)")):
    for i, (ad, p) in enumerate(veri.items()):
        xs, ys = p.exterior.xy
        ax.fill(xs, ys, color=plt.cm.tab20(i % 20), alpha=.55, ec="k", lw=.8)
        c = p.representative_point(); ax.text(c.x, c.y, ad, ha="center", fontsize=8)
    ax.set_aspect(1 / math.cos(math.radians(40.98))); ax.set_title(baslik); ax.axis("off")
plt.tight_layout(); plt.savefig(out / "once-sonra.png", dpi=110)
