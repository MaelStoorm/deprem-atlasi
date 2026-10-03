// Kadıköy Deprem Atlası — internetsiz çalışma.
// Uygulama HER ZAMAN önce telefondaki kopyadan açılır (internet beklemez, zayıf çekimde takılmaz).
// İnternet varsa arka planda yeni sürüm indirilir; bir sonraki açılışta o gösterilir.
const SURUM = "atlas-v5";
const TEMEL = ["./", "./index.html", "./gizlilik.html", "./manifest.webmanifest", "./ikon-192.png", "./ikon-512.png", "./ikon-180.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(SURUM).then(c => c.addAll(TEMEL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(a => Promise.all(a.filter(k => k !== SURUM).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

// Arka planda güncelle: başarılı olursa kopyayı yeniler, hata olursa sessizce geçer
function guncelle(istek, anahtar) {
  return fetch(istek).then(y => {
    if (y && (y.ok || y.type === "opaque")) { const k = y.clone(); caches.open(SURUM).then(c => c.put(anahtar || istek, k)); }
    return y;
  });
}

self.addEventListener("fetch", e => {
  const r = e.request; if (r.method !== "GET") return;
  if (r.mode === "navigate") {
    // Sayfa: önce kopya; kopya yoksa (ilk açılış) internet
    const ag = guncelle(r, "./index.html").catch(() => null);
    e.waitUntil(ag);
    e.respondWith(caches.match("./index.html").then(v => v || ag.then(y => y || caches.match("./"))));
    return;
  }
  // Diğer dosyalar (simgeler, yazı tipi): önce kopya, yoksa internet
  e.respondWith(caches.match(r, { ignoreSearch: r.url.startsWith(self.location.origin) }).then(v => {
    if (v) return v;
    return guncelle(r).catch(() => new Response("", { status: 504 }));
  }));
});
