#!/bin/bash
# iOS uygulamasının site klasör(ler)ini hazırlar (GitHub Actions'ta derlemeden önce çalışır).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 ios/site.py --html index.html --out ios/gen/DepremAtlasi/site --copy gizlilik.html yazi.ttf yazi-lisans.txt ikon-180.png ikon-192.png ikon-512.png manifest.webmanifest
