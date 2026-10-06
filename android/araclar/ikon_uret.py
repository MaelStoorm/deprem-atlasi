"""Uygulama simgelerini sitedeki ikon-maskable-512.png dosyasından üretir.

Kullanım (depo kökünden):  python3 android/araclar/ikon_uret.py
Gerekli: Pillow (pip install pillow)

Üretilenler (android/app/src/main/res altında):
  mipmap-*/ic_launcher_foreground.png   uyarlanabilir simgenin ön katmanı (beyaz işaret, saydam zemin)
  mipmap-*/ic_launcher.png              Android 7.x için köşeleri yuvarlatılmış kare simge
  mipmap-*/ic_launcher_round.png        Android 7.x için yuvarlak simge
Zemin rengi values/colors.xml içindeki ic_launcher_background'dur (simgenin kenar rengi).
Android 13+ temalı (tek renkli) simge de aynı ön katmanı kullanır.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw

KOK = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KAYNAK = os.path.join(KOK, "ikon-maskable-512.png")
RES = os.path.join(KOK, "android", "app", "src", "main", "res")

YOGUNLUK = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
# Maskable simgenin tamamı 108 dp'lik katmanda bu boyuta (dp) yerleşir. İşaretin en uzak noktası
# merkezden genişliğin %35'i kadar uzakta; 83 dp ile işaret 66 dp'lik güvenli dairenin içinde kalır.
YERLESIM_DP = 83


def isareti_ayir(im):
    """Düz renkli zemin üzerindeki beyaz işareti saydam zeminli beyaz bir katmana çevirir."""
    im = im.convert("RGB")
    zemin = im.getpixel((0, 0))
    kanallar = []
    for c, z in zip(im.split(), zemin):
        # renk = a*255 + (1-a)*zemin  →  a = (renk - zemin) / (255 - zemin)
        kanallar.append(c.point(lambda v, z=z: max(0, min(255, round((v - z) * 255 / max(1, 255 - z))))))
    alfa = ImageChops.lighter(ImageChops.lighter(kanallar[0], kanallar[1]), kanallar[2])
    beyaz = Image.new("RGBA", im.size, (255, 255, 255, 0))
    beyaz.putalpha(alfa)
    return beyaz, zemin


def on_katman(isaret, piksel):
    tuval = Image.new("RGBA", (piksel, piksel), (0, 0, 0, 0))
    boy = round(piksel * YERLESIM_DP / 108)
    k = isaret.resize((boy, boy), Image.LANCZOS)
    tuval.alpha_composite(k, ((piksel - boy) // 2, (piksel - boy) // 2))
    return tuval


def eski_simge(isaret, zemin, piksel, yuvarlak):
    # 108 dp'lik katmanın ortadaki 72 dp'si görünür; 48 dp'lik simgeye o bölüm sığdırılır
    buyuk = piksel * 108 // 72
    tam = Image.new("RGBA", (buyuk, buyuk), zemin + (255,))
    tam.alpha_composite(on_katman(isaret, buyuk))
    kes = (buyuk - piksel) // 2
    goruntu = tam.crop((kes, kes, kes + piksel, kes + piksel))
    olcek = 4
    maske = Image.new("L", (piksel * olcek, piksel * olcek), 0)
    ciz = ImageDraw.Draw(maske)
    if yuvarlak:
        ciz.ellipse((0, 0, piksel * olcek - 1, piksel * olcek - 1), fill=255)
    else:
        ciz.rounded_rectangle((0, 0, piksel * olcek - 1, piksel * olcek - 1), radius=piksel * olcek * 0.18, fill=255)
    goruntu.putalpha(maske.resize((piksel, piksel), Image.LANCZOS))
    return goruntu


def main():
    isaret, zemin = isareti_ayir(Image.open(KAYNAK))
    print("zemin rengi: #%02X%02X%02X" % zemin)
    for ad, carpan in YOGUNLUK.items():
        klasor = os.path.join(RES, "mipmap-" + ad)
        os.makedirs(klasor, exist_ok=True)
        on = on_katman(isaret, round(108 * carpan))
        on.save(os.path.join(klasor, "ic_launcher_foreground.png"), optimize=True)
        eski_simge(isaret, zemin, round(48 * carpan), False).save(os.path.join(klasor, "ic_launcher.png"), optimize=True)
        eski_simge(isaret, zemin, round(48 * carpan), True).save(os.path.join(klasor, "ic_launcher_round.png"), optimize=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
